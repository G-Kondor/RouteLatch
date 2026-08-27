import Combine
import CoreLocation
import Foundation
import HealthKit
import OSLog

private let workoutLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RouteLatch", category: "Workout")

@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    struct Completion: Sendable {
        let workoutSaved: Bool
        let routeSaved: Bool
    }

    @Published private(set) var heartRate: Double?
    @Published private(set) var authorizationDenied = false
    @Published private(set) var errorMessage: String?
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var locationBuffer: [CLLocation] = []
    private var routeInsertion: Task<Void, Error>?
    private var insertedLocationCount = 0

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            authorizationDenied = true
            return false
        }
        let workout = HKObjectType.workoutType()
        let route = HKSeriesType.workoutRoute()
        do {
            try await healthStore.requestAuthorization(toShare: [workout, route], read: [heartRate])
            let authorized = healthStore.authorizationStatus(for: workout) == .sharingAuthorized
                && healthStore.authorizationStatus(for: route) == .sharingAuthorized
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
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        locationBuffer.removeAll(keepingCapacity: true)
        routeInsertion = nil
        insertedLocationCount = 0
        errorMessage = nil
        let start = Date()
        session.startActivity(with: start)
        try await builder.beginCollection(at: start)
    }

    func addActualLocation(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 75 else { return }
        locationBuffer.append(location)
        if locationBuffer.count >= 20 { enqueueBufferedLocations() }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    func finish() async throws -> Completion {
        session?.end()
        guard let builder else {
            clear()
            return Completion(workoutSaved: false, routeSaved: false)
        }
        enqueueBufferedLocations()
        var routeDataSucceeded = true
        do { try await routeInsertion?.value }
        catch {
            routeDataSucceeded = false
            workoutLogger.error("Workout route insertion failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Some location samples could not be added to the workout route."
        }

        do {
            try await builder.endCollection(at: .now)
            guard let workout = try await builder.finishWorkout() else {
                clear()
                return Completion(workoutSaved: false, routeSaved: false)
            }
            var routeSaved = false
            if routeDataSucceeded, insertedLocationCount > 0, let routeBuilder {
                do {
                    _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
                    routeSaved = true
                } catch {
                    workoutLogger.error("Workout route finalization failed: \(error.localizedDescription, privacy: .public)")
                    errorMessage = "The run was saved, but its location route could not be saved."
                }
            }
            clear()
            return Completion(workoutSaved: true, routeSaved: routeSaved)
        } catch {
            workoutLogger.error("Workout finalization failed: \(error.localizedDescription, privacy: .public)")
            clear()
            throw error
        }
    }

    private func enqueueBufferedLocations() {
        guard !locationBuffer.isEmpty, let routeBuilder else { return }
        let locations = locationBuffer
        locationBuffer.removeAll(keepingCapacity: true)
        let previous = routeInsertion
        routeInsertion = Task { @MainActor in
            try await previous?.value
            try await withCheckedThrowingContinuation { continuation in
                routeBuilder.insertRouteData(locations) { success, error in
                    if success { continuation.resume() }
                    else { continuation.resume(throwing: error ?? WorkoutManagerError.routeInsertionFailed) }
                }
            }
            insertedLocationCount += locations.count
        }
    }

    private func clear() {
        session = nil
        builder = nil
        routeBuilder = nil
        routeInsertion = nil
        locationBuffer.removeAll()
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
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate), collectedTypes.contains(type),
              let value = workoutBuilder.statistics(for: type)?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) else { return }
        Task { @MainActor in heartRate = value }
    }
}
