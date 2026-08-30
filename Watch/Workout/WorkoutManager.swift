import Combine
import CoreLocation
import Foundation
import HealthKit
import OSLog
import RouteLatchCore

private let workoutLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RouteLatch", category: "Workout")

@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    struct Completion: Sendable {
        let workoutSaved: Bool
        let routeSaved: Bool
        let actualDistance: Double
        let startedAt: Date
        let endedAt: Date
        let points: [RecordedRunPoint]
    }

    @Published private(set) var heartRate: Double?
    @Published private(set) var distance: Double = 0
    @Published private(set) var authorizationDenied = false
    @Published private(set) var errorMessage: String?
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var locationBuffer: [CLLocation] = []
    private var recordedPoints: [RecordedRunPoint] = []
    private var routeInsertion: Task<Void, Never>?
    private var insertedLocationCount = 0
    private var routeDataFailed = false
    private var routeWarning: String?
    private var workoutStartedAt: Date?
    private var lastAcceptedLocationTimestamp: Date?
    private var fallbackDistance = RunDistanceAccumulator()
    private var canSaveWorkoutRoute = false

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate),
              let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            authorizationDenied = true
            return false
        }
        let workout = HKObjectType.workoutType()
        let route = HKSeriesType.workoutRoute()
        let shareTypes: Set<HKSampleType> = [workout, route]
        let readTypes: Set<HKObjectType> = [heartRate, distance]
        do {
            let currentWorkoutStatus = healthStore.authorizationStatus(for: workout)
            canSaveWorkoutRoute = healthStore.authorizationStatus(for: route) == .sharingAuthorized

            // `requestAuthorization` may keep the Watch app waiting for user UI
            // even when the user has already answered every permission. Ask
            // HealthKit first; the common repeat-run path should return here.
            let requestStatus = try await healthStore.statusForAuthorizationRequest(
                toShare: shareTypes,
                read: readTypes
            )
            if requestStatus == .unnecessary {
                let authorized = currentWorkoutStatus == .sharingAuthorized
                authorizationDenied = !authorized
                return authorized
            }

            // A denied write permission cannot be re-prompted by repeatedly
            // calling requestAuthorization. Let the UI direct the user to Settings.
            if currentWorkoutStatus == .sharingDenied {
                authorizationDenied = true
                return false
            }

            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
            let authorized = healthStore.authorizationStatus(for: workout) == .sharingAuthorized
            canSaveWorkoutRoute = healthStore.authorizationStatus(for: route) == .sharingAuthorized
            authorizationDenied = !authorized
            return authorized
        } catch {
            authorizationDenied = true
            workoutLogger.error("Health authorization failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    func start() async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        routeBuilder = canSaveWorkoutRoute ? HKWorkoutRouteBuilder(healthStore: healthStore, device: .local()) : nil
        locationBuffer.removeAll(keepingCapacity: true)
        recordedPoints.removeAll(keepingCapacity: true)
        routeInsertion = nil
        insertedLocationCount = 0
        routeDataFailed = false
        routeWarning = nil
        lastAcceptedLocationTimestamp = nil
        fallbackDistance.reset()
        distance = 0
        heartRate = nil
        errorMessage = nil
        let start = Date()
        workoutStartedAt = start
        session.startActivity(with: start)
        try await builder.beginCollection(at: start)
    }

    func addActualLocation(_ location: CLLocation) {
        guard let workoutStartedAt,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 75,
              location.timestamp >= workoutStartedAt,
              location.timestamp <= Date().addingTimeInterval(10),
              lastAcceptedLocationTimestamp.map({ location.timestamp > $0 }) ?? true else { return }
        lastAcceptedLocationTimestamp = location.timestamp
        if routeBuilder != nil { locationBuffer.append(location) }
        let fallback = fallbackDistance.add(.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        ))
        if let healthDistance = healthKitDistance(from: builder) {
            distance = healthDistance
        } else {
            distance = fallback
        }
        recordedPoints.append(.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elevation: location.verticalAccuracy >= 0 ? location.altitude : nil,
            timestamp: location.timestamp,
            heartRate: heartRate
        ))
        if locationBuffer.count >= 20 { enqueueBufferedLocations() }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    func cancelPendingStart() {
        session?.end()
        builder?.discardWorkout()
        clear()
    }

    func finish() async throws -> Completion {
        let endedAt = Date()
        let startedAt = workoutStartedAt ?? endedAt
        let points = recordedPoints
        session?.end()
        guard let builder else {
            let finalDistance = distance
            clear()
            return Completion(
                workoutSaved: false,
                routeSaved: false,
                actualDistance: finalDistance,
                startedAt: startedAt,
                endedAt: endedAt,
                points: points
            )
        }
        enqueueBufferedLocations()
        await routeInsertion?.value
        let provisionalDistance = healthKitDistance(from: builder) ?? fallbackDistance.distance

        do {
            try await builder.endCollection(at: .now)
            let finalDistance = healthKitDistance(from: builder) ?? provisionalDistance
            guard let workout = try await builder.finishWorkout() else {
                clear()
                return Completion(
                    workoutSaved: false,
                    routeSaved: false,
                    actualDistance: finalDistance,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    points: points
                )
            }
            var routeSaved = false
            if insertedLocationCount > 0, let routeBuilder {
                do {
                    _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
                    routeSaved = true
                } catch {
                    workoutLogger.error("Workout route finalization failed: \(error.localizedDescription, privacy: .public)")
                    errorMessage = "The run was saved, but its location route could not be saved."
                }
            }
            if routeSaved, routeDataFailed { errorMessage = routeWarning }
            clear()
            return Completion(
                workoutSaved: true,
                routeSaved: routeSaved,
                actualDistance: finalDistance,
                startedAt: startedAt,
                endedAt: endedAt,
                points: points
            )
        } catch {
            workoutLogger.error("Workout finalization failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "The Health workout could not be finalized, but the run is still queued for Strava."
            clear()
            return Completion(
                workoutSaved: false,
                routeSaved: false,
                actualDistance: provisionalDistance,
                startedAt: startedAt,
                endedAt: endedAt,
                points: points
            )
        }
    }

    private func enqueueBufferedLocations() {
        guard !locationBuffer.isEmpty, let routeBuilder else { return }
        let locations = locationBuffer
            .sorted { $0.timestamp < $1.timestamp }
        locationBuffer.removeAll(keepingCapacity: true)
        let previous = routeInsertion
        routeInsertion = Task { @MainActor in
            await previous?.value
            do {
                try await withCheckedThrowingContinuation { continuation in
                    routeBuilder.insertRouteData(locations) { success, error in
                        if success { continuation.resume() }
                        else { continuation.resume(throwing: error ?? WorkoutManagerError.routeInsertionFailed) }
                    }
                }
                insertedLocationCount += locations.count
            } catch {
                routeDataFailed = true
                routeWarning = "The workout was saved, but some GPS samples could not be attached to its route."
                workoutLogger.error("Workout route insertion failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func healthKitDistance(from builder: HKLiveWorkoutBuilder?) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
              let value = builder?.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()),
              value.isFinite, value > 0 else { return nil }
        return value
    }

    private func clear() {
        session = nil
        builder = nil
        routeBuilder = nil
        routeInsertion = nil
        locationBuffer.removeAll()
        recordedPoints.removeAll()
        workoutStartedAt = nil
        lastAcceptedLocationTimestamp = nil
    }
}

private enum WorkoutManagerError: Error { case routeInsertionFailed }

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        workoutLogger.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in errorMessage = error.localizedDescription }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        let heartRate = heartRateType.flatMap { type in
            collectedTypes.contains(type)
                ? workoutBuilder.statistics(for: type)?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
                : nil
        }
        let distance = distanceType.flatMap { type in
            collectedTypes.contains(type)
                ? workoutBuilder.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter())
                : nil
        }
        Task { @MainActor in
            if let heartRate { self.heartRate = heartRate }
            if let distance, distance.isFinite, distance >= 0 { self.distance = distance }
        }
    }
}
