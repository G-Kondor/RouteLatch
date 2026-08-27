import Combine
import CoreLocation
import Foundation
import RouteLatchCore
import WatchKit

@MainActor
final class RouteNavigationModel: NSObject, ObservableObject {
    enum Phase: Equatable { case ready, starting, active, paused, finishing, finished }

    struct Summary {
        let elapsed: TimeInterval
        let distanceCompleted: Double
        let heartRate: Double?
        let paceProgress: PaceProgress?
        let workoutSaved: Bool
        let routeSaved: Bool
    }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var location: CLLocation?
    @Published private(set) var match: RouteMatch?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var heartRate: Double?
    @Published private(set) var isOffCourse = false
    @Published private(set) var paceProgress: PaceProgress?
    @Published private(set) var isBehindPace = false
    @Published private(set) var distanceCompleted = 0.0
    @Published private(set) var summary: Summary?
    @Published var errorMessage: String?
    let route: Route
    private let workout = WorkoutManager()
    private let locationManager = CLLocationManager()
    private var matcher: RouteMatcher
    private var alertState = OffCourseAlertState()
    private var paceAlertState = PaceAlertState()
    private var guidanceStartDistanceAlong: Double?
    private var didSignalFinish = false
    private nonisolated(unsafe) var timer: Timer?
    private var activePeriodStartedAt: Date?
    private var accumulatedElapsed: TimeInterval = 0
    private var awaitingLocationAuthorization = false
    private var workoutCancellables: Set<AnyCancellable> = []

    init(route: Route) {
        self.route = route
        matcher = RouteMatcher(route: route)
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        workout.$heartRate.sink { [weak self] in self?.heartRate = $0 }.store(in: &workoutCancellables)
        workout.$errorMessage.compactMap { $0 }.sink { [weak self] in self?.errorMessage = $0 }.store(in: &workoutCancellables)
    }

    func start() {
        guard phase == .ready else { return }
        phase = .starting
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginWorkout()
        case .notDetermined:
            awaitingLocationAuthorization = true
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            phase = .ready
            errorMessage = "Location permission is required for live route guidance. You can enable it in Settings."
        @unknown default:
            phase = .ready
            errorMessage = "RouteLatch could not determine location permission."
        }
    }

    private func beginWorkout() {
        Task {
            guard await workout.requestAuthorization() else {
                phase = .ready
                errorMessage = "Health access was denied. RouteLatch cannot provide reliable background workout guidance."
                return
            }
            do {
                try await workout.start()
                locationManager.startUpdatingLocation()
                accumulatedElapsed = 0
                elapsed = 0
                activePeriodStartedAt = .now
                summary = nil
                didSignalFinish = false
                guidanceStartDistanceAlong = nil
                distanceCompleted = 0
                paceProgress = nil
                isBehindPace = false
                paceAlertState = PaceAlertState()
                phase = .active
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.refreshElapsed() }
                }
            } catch {
                phase = .ready
                errorMessage = "The running workout could not start: \(error.localizedDescription)"
            }
        }
    }

    func pause() {
        guard phase == .active else { return }
        refreshElapsed()
        accumulatedElapsed = elapsed
        activePeriodStartedAt = nil
        phase = .paused
        locationManager.stopUpdatingLocation()
        workout.pause()
    }

    func resume() {
        guard phase == .paused else { return }
        activePeriodStartedAt = .now
        phase = .active
        locationManager.startUpdatingLocation()
        workout.resume()
    }

    func finish() {
        guard phase == .active || phase == .paused else { return }
        refreshElapsed()
        phase = .finishing
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        activePeriodStartedAt = nil
        let finalElapsed = elapsed
        let finalDistance = distanceCompleted
        let finalHeartRate = heartRate
        let finalPaceProgress = paceProgress
        Task {
            do {
                let completion = try await workout.finish()
                summary = Summary(
                    elapsed: finalElapsed,
                    distanceCompleted: finalDistance,
                    heartRate: finalHeartRate,
                    paceProgress: finalPaceProgress,
                    workoutSaved: completion.workoutSaved,
                    routeSaved: completion.routeSaved
                )
            } catch {
                summary = Summary(elapsed: finalElapsed, distanceCompleted: finalDistance, heartRate: finalHeartRate, paceProgress: finalPaceProgress, workoutSaved: false, routeSaved: false)
                errorMessage = "The run ended, but the workout could not be saved: \(error.localizedDescription)"
            }
            phase = .finished
        }
    }

    private func refreshElapsed(playPaceHaptics: Bool = true) {
        elapsed = accumulatedElapsed + (activePeriodStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
        refreshPaceStatus(playHaptics: playPaceHaptics)
    }

    private func refreshPaceStatus(playHaptics: Bool) {
        guard let target = route.targetPaceSecondsPerKilometer,
              let progress = PaceCalculator.progress(
                targetPaceSecondsPerKilometer: target,
                elapsed: elapsed,
                distanceCompleted: distanceCompleted,
                plannedDistance: max(1, route.totalDistance - (guidanceStartDistanceAlong ?? 0))
              ) else {
            paceProgress = nil
            isBehindPace = false
            return
        }
        paceProgress = progress
        guard !isOffCourse else { return }
        let event = paceAlertState.update(
            averagePace: progress.averagePaceSecondsPerKilometer,
            targetPace: target,
            distanceCompleted: distanceCompleted,
            elapsed: elapsed
        )
        isBehindPace = paceAlertState.isBehind
        guard playHaptics else { return }
        switch event {
        case .fellBehind, .repeatWarning: WKInterfaceDevice.current().play(.notification)
        case .caughtUp: WKInterfaceDevice.current().play(.directionUp)
        case .none: break
        }
    }

    deinit { timer?.invalidate() }
}

extension RouteNavigationModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            guard phase == .active, latest.timestamp.timeIntervalSinceNow > -15 else { return }
            location = latest
            workout.addActualLocation(latest)
            do {
                let value = try matcher.match(
                    latitude: latest.coordinate.latitude,
                    longitude: latest.coordinate.longitude,
                    horizontalAccuracy: latest.horizontalAccuracy
                )
                match = value
                if guidanceStartDistanceAlong == nil { guidanceStartDistanceAlong = value.distanceAlongRoute }
                distanceCompleted = max(
                    distanceCompleted,
                    max(0, value.distanceAlongRoute - (guidanceStartDistanceAlong ?? value.distanceAlongRoute))
                )
                let alertEvent = alertState.update(distance: value.distanceFromRoute)
                isOffCourse = alertState.isOffCourse
                switch alertEvent {
                case .wentOffCourse, .repeatWarning: WKInterfaceDevice.current().play(.retry)
                case .returnedToRoute: WKInterfaceDevice.current().play(.success)
                case .none: break
                }
                let reachedFinish = !didSignalFinish && value.progress > 0.98 && route.totalDistance - value.distanceAlongRoute < 25
                refreshElapsed(playPaceHaptics: alertEvent == .none && !reachedFinish)
                if reachedFinish {
                    didSignalFinish = true
                    WKInterfaceDevice.current().play(.success)
                }
            } catch RouteMatchingError.poorHorizontalAccuracy { return }
            catch { errorMessage = error.localizedDescription }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in errorMessage = "Location is unavailable: \(error.localizedDescription)" }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedAlways || status == .authorizedWhenInUse, awaitingLocationAuthorization {
                awaitingLocationAuthorization = false
                beginWorkout()
            } else if status == .denied || status == .restricted {
                awaitingLocationAuthorization = false
                if phase == .starting { phase = .ready }
                errorMessage = "Location permission is required for route guidance."
            }
        }
    }
}
