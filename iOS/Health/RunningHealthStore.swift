import CoreLocation
import Foundation
import HealthKit
import RouteLatchCore

enum HealthAccess: Equatable {
    case unavailable
    case notRequested
    case requested
}

/// Reads running workouts the Watch (and any other source) already saved in
/// Apple Health. It does not create samples and it does not fill in missing runs.
@MainActor
final class RunningHealthStore: ObservableObject {
    static let requestedKey = "RouteLatch.analytics.healthReadRequested"

    @Published private(set) var runs: [ImportedHealthRun] = []
    @Published private(set) var access: HealthAccess
    @Published private(set) var isLoading = false
    @Published private(set) var hasFetched = false
    @Published private(set) var revision = 0
    @Published private(set) var statusMessage: String?

    private let store = HKHealthStore()
    private var lastFetch: Date?

    init() {
        if !HKHealthStore.isHealthDataAvailable() {
            access = .unavailable
        } else if UserDefaults.standard.bool(forKey: Self.requestedKey) {
            access = .requested
        } else {
            access = .notRequested
        }
    }

    func allowAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            access = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            UserDefaults.standard.set(true, forKey: Self.requestedKey)
            access = .requested
            await refresh(force: true)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refresh(force: Bool = false) async {
        guard access == .requested, HKHealthStore.isHealthDataAvailable() else { return }
        if isLoading { return }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 15 { return }
        isLoading = true
        defer {
            isLoading = false
            hasFetched = true
        }
        do {
            runs = try await loadRuns()
            revision += 1
            statusMessage = nil
            lastFetch = Date()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        let identifiers: [HKQuantityTypeIdentifier] = [.heartRate, .distanceWalkingRunning, .activeEnergyBurned, .stepCount]
        for identifier in identifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    private func loadRuns() async throws -> [ImportedHealthRun] {
        let workouts = try await fetchWorkouts()
        var imported: [ImportedHealthRun] = []
        imported.reserveCapacity(workouts.count)
        for (index, workout) in workouts.enumerated() {
            if let run = await importWorkout(workout, includeRoute: index < 8) {
                imported.append(run)
            }
        }
        return imported.sorted { $0.startedAt > $1.startedAt }
    }

    private func fetchWorkouts() async throws -> [HKWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -400, to: Date())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: start, end: Date().addingTimeInterval(60), options: .strictStartDate)
        ])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 180,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    private func importWorkout(_ workout: HKWorkout, includeRoute: Bool) async -> ImportedHealthRun? {
        let distance = await sum(.distanceWalkingRunning, workout: workout, unit: .meter())
        let duration = workout.duration
        guard duration > 0 || (distance ?? 0) > 0 else { return nil }
        async let energy = sum(.activeEnergyBurned, workout: workout, unit: .kilocalorie())
        async let steps = sum(.stepCount, workout: workout, unit: .count())
        async let averageHeartRate = average(.heartRate, workout: workout)
        async let heart = heartRateSamples(for: workout)
        async let route = includeRoute ? routeTrack(for: workout) : []
        let indoor = indoorFlag(in: workout)
        return ImportedHealthRun(
            id: workout.uuid.uuidString,
            name: indoor ? "Indoor run" : "Run",
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            duration: duration,
            distanceMeters: distance,
            elevationGainMeters: elevationGain(of: workout),
            averageHeartRate: await averageHeartRate,
            heartRateSamples: await heart,
            stepCount: await steps,
            activeEnergyKilocalories: await energy,
            track: await route
        )
    }

    private func sum(_ identifier: HKQuantityTypeIdentifier, workout: HKWorkout, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        if let value = workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: unit), value.isFinite, value > 0 {
            return value
        }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForObjects(from: workout),
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
            }
            store.execute(query)
        }
    }

    private func average(_ identifier: HKQuantityTypeIdentifier, workout: HKWorkout) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        if let value = workout.statistics(for: type)?.averageQuantity()?.doubleValue(for: unit), value.isFinite, value > 0 {
            return value
        }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForObjects(from: workout),
                options: .discreteAverage
            ) { _, statistics, _ in
                let value = statistics?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
            }
            store.execute(query)
        }
    }

    private func heartRateSamples(for workout: HKWorkout) async -> [AnalyticsHeartRateSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples: [HKQuantitySample] = await samples(type: type, predicate: HKQuery.predicateForObjects(from: workout), limit: 4_000)
        let series = samples.compactMap { sample -> AnalyticsHeartRateSample? in
            let bpm = sample.quantity.doubleValue(for: unit)
            guard bpm.isFinite else { return nil }
            return AnalyticsHeartRateSample(timestamp: sample.startDate, beatsPerMinute: bpm)
        }
        return RunAnalytics.thinnedHeartRateSamples(series)
    }

    private func routeTrack(for workout: HKWorkout) async -> [AnalyticsTrackSample] {
        let routes: [HKWorkoutRoute] = await samples(
            type: HKSeriesType.workoutRoute(),
            predicate: HKQuery.predicateForObjects(from: workout),
            limit: 1
        )
        guard let route = routes.first else { return [] }
        let locations = await locations(on: route).sorted { $0.timestamp < $1.timestamp }
        let capped = downsample(locations, limit: 8_000)
        return capped.map { location in
            let usableFix = location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 100
            return AnalyticsTrackSample(
                latitude: usableFix ? location.coordinate.latitude : nil,
                longitude: usableFix ? location.coordinate.longitude : nil,
                elevationMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
                timestamp: location.timestamp
            )
        }
    }

    private func locations(on route: HKWorkoutRoute) async -> [CLLocation] {
        let accumulator = RouteAccumulator()
        return await withCheckedContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                if let batch { accumulator.append(batch) }
                if done || error != nil, let locations = accumulator.take() {
                    continuation.resume(returning: locations)
                }
            }
            store.execute(query)
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if let locations = accumulator.take() {
                    continuation.resume(returning: locations)
                }
            }
        }
    }

    private func samples<T: HKSample>(type: HKSampleType, predicate: NSPredicate, limit: Int) async -> [T] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [T]) ?? [])
            }
            store.execute(query)
        }
    }

    private func elevationGain(of workout: HKWorkout) -> Double? {
        let metadata = workout.metadata?[HKMetadataKeyElevationAscended]
        let meters: Double?
        if let quantity = metadata as? HKQuantity {
            meters = quantity.doubleValue(for: .meter())
        } else if let number = metadata as? NSNumber {
            meters = number.doubleValue
        } else {
            meters = nil
        }
        guard let meters, meters.isFinite, meters >= 0 else { return nil }
        return meters
    }

    private func indoorFlag(in workout: HKWorkout) -> Bool {
        if let number = workout.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber { return number.boolValue }
        if let flag = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool { return flag }
        return false
    }

    private func downsample(_ locations: [CLLocation], limit: Int) -> [CLLocation] {
        guard locations.count > limit, limit > 0 else { return locations }
        let step = Int((Double(locations.count) / Double(limit)).rounded(.up))
        return locations.enumerated().compactMap { index, location in
            index % step == 0 || index == locations.count - 1 ? location : nil
        }
    }
}

private final class RouteAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var locations: [CLLocation] = []
    private var finished = false

    func append(_ batch: [CLLocation]) {
        lock.lock()
        if !finished { locations.append(contentsOf: batch) }
        lock.unlock()
    }

    func take() -> [CLLocation]? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return nil }
        finished = true
        return locations
    }
}
