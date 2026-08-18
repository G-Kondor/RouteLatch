import Combine
import CoreLocation
import Foundation
import HealthKit

@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    @Published private(set) var heartRate: Double?
    @Published private(set) var authorizationDenied = false
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else { authorizationDenied = true; return false }
        let workout = HKObjectType.workoutType()
        let route = HKSeriesType.workoutRoute()
        do {
            try await healthStore.requestAuthorization(toShare: [workout, route], read: [heartRate])
            return true
        } catch { authorizationDenied = true; return false }
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
        let start = Date()
        session.startActivity(with: start)
        try await builder.beginCollection(at: start)
    }

    func addActualLocation(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 75 else { return }
        routeBuilder?.insertRouteData([location]) { _, _ in }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    func finish() async {
        session?.end()
        guard let builder else { clear(); return }
        do {
            try await builder.endCollection(at: .now)
            if let workout = try await builder.finishWorkout() {
                _ = try? await routeBuilder?.finishRoute(with: workout, metadata: nil)
            }
        } catch {}
        clear()
    }

    private func clear() { session = nil; builder = nil; routeBuilder = nil }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate), collectedTypes.contains(type),
              let value = workoutBuilder.statistics(for: type)?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) else { return }
        Task { @MainActor in heartRate = value }
    }
}
