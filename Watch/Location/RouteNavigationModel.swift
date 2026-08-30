import Combine
import CoreLocation
import Foundation
import RouteLatchCore
import WatchKit
import WidgetKit

@MainActor
final class RouteNavigationModel: NSObject, ObservableObject {
    enum Phase: Equatable { case ready, starting, active, paused, finishing, finished }

    enum StartStage: Equatable {
        case locationPermission
        case healthPermission
        case workout

        var message: String {
            switch self {
            case .locationPermission: "Waiting for Location access…"
            case .healthPermission: "Checking Health access…"
            case .workout: "Starting workout…"
            }
        }
    }

    struct Summary {
        let elapsed: TimeInterval
        let actualDistance: Double
        let averagePace: Double?
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
    @Published private(set) var actualDistance = 0.0
    @Published private(set) var routeDistanceCompleted = 0.0
    @Published private(set) var summary: Summary?
    @Published private(set) var startStage: StartStage?
    @Published var errorMessage: String?
    let route: Route?
    let targetPaceSecondsPerKilometer: Double?
    private let workout = WorkoutManager()
    private let locationManager = CLLocationManager()
    private var matcher: RouteMatcher?
    private var alertState = OffCourseAlertState()
    private var paceAlertState = PaceAlertState()
    private var guidanceStartDistanceAlong: Double?
    private var didSignalFinish = false
    private nonisolated(unsafe) var timer: Timer?
    private var activePeriodStartedAt: Date?
    private var accumulatedElapsed: TimeInterval = 0
    private var awaitingLocationAuthorization = false
    private var workoutCancellables: Set<AnyCancellable> = []
    private var lastWidgetReload = Date.distantPast
    private var startAttemptID: UUID?
    private var startTask: Task<Void, Never>?
    private var startTimeoutTask: Task<Void, Never>?

    init(route: Route?, freeRunTargetPaceSecondsPerKilometer: Double? = nil) {
        self.route = route
        let selectedTarget = route?.targetPaceSecondsPerKilometer ?? freeRunTargetPaceSecondsPerKilometer
        targetPaceSecondsPerKilometer = selectedTarget.flatMap { PaceGoalConfiguration.isValid($0) ? $0 : nil }
        matcher = route.map(RouteMatcher.init(route:))
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        workout.$heartRate.sink { [weak self] in self?.heartRate = $0 }.store(in: &workoutCancellables)
        workout.$distance.sink { [weak self] distance in
            guard let self else { return }
            actualDistance = distance
            if phase == .active || phase == .paused { refreshPaceStatus(playHaptics: false) }
        }.store(in: &workoutCancellables)
        workout.$errorMessage.compactMap { $0 }.sink { [weak self] in self?.errorMessage = $0 }.store(in: &workoutCancellables)
    }

    func start() {
        guard phase == .ready else { return }
        let attemptID = UUID()
        startAttemptID = attemptID
        phase = .starting
        startStage = .locationPermission
        scheduleStartTimeout(for: attemptID)
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginWorkout(for: attemptID)
        case .notDetermined:
            awaitingLocationAuthorization = true
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            failStart(
                attemptID: attemptID,
                message: "Location permission is required to track an outdoor run. You can enable it in Settings."
            )
        @unknown default:
            failStart(attemptID: attemptID, message: "RouteLatch could not determine location permission.")
        }
    }

    func cancelStart() {
        guard phase == .starting else { return }
        awaitingLocationAuthorization = false
        startTask?.cancel()
        workout.cancelPendingStart()
        clearStartAttempt()
        phase = .ready
    }

    private func beginWorkout(for attemptID: UUID) {
        guard startAttemptID == attemptID, phase == .starting else { return }
        startStage = .healthPermission
        startTask = Task { [weak self] in
            guard let self else { return }
            guard await workout.requestAuthorization() else {
                guard startAttemptID == attemptID else { return }
                failStart(
                    attemptID: attemptID,
                    message: "Health workout access is disabled. Enable it in Settings, then try again."
                )
                return
            }
            guard startAttemptID == attemptID, !Task.isCancelled else { return }
            startStage = .workout
            do {
                try await workout.start()
                guard startAttemptID == attemptID, !Task.isCancelled else {
                    workout.cancelPendingStart()
                    return
                }
                WorkoutWidgetStore.discardPendingCommand()
                locationManager.startUpdatingLocation()
                accumulatedElapsed = 0
                elapsed = 0
                activePeriodStartedAt = .now
                summary = nil
                didSignalFinish = false
                guidanceStartDistanceAlong = nil
                actualDistance = 0
                routeDistanceCompleted = 0
                paceProgress = nil
                isBehindPace = false
                paceAlertState = PaceAlertState()
                clearStartAttempt()
                phase = .active
                publishWidgetSnapshot(forceReload: true)
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.refreshElapsed() }
                }
            } catch {
                workout.cancelPendingStart()
                guard startAttemptID == attemptID else { return }
                failStart(attemptID: attemptID, message: "The running workout could not start: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleStartTimeout(for attemptID: UUID) {
        startTimeoutTask?.cancel()
        startTimeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) }
            catch { return }
            guard let self, startAttemptID == attemptID, phase == .starting else { return }
            awaitingLocationAuthorization = false
            startTask?.cancel()
            workout.cancelPendingStart()
            clearStartAttempt()
            phase = .ready
            errorMessage = "Starting took too long. Check the Location and Health permission prompts, then try again."
        }
    }

    private func failStart(attemptID: UUID, message: String) {
        guard startAttemptID == attemptID else { return }
        awaitingLocationAuthorization = false
        clearStartAttempt()
        phase = .ready
        errorMessage = message
    }

    private func clearStartAttempt() {
        startAttemptID = nil
        startStage = nil
        startTask = nil
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
    }

    func pause() {
        guard phase == .active else { return }
        refreshElapsed()
        accumulatedElapsed = elapsed
        activePeriodStartedAt = nil
        phase = .paused
        locationManager.stopUpdatingLocation()
        workout.pause()
        publishWidgetSnapshot(forceReload: true)
    }

    func resume() {
        guard phase == .paused else { return }
        activePeriodStartedAt = .now
        phase = .active
        locationManager.startUpdatingLocation()
        workout.resume()
        publishWidgetSnapshot(forceReload: true)
    }

    func finish() {
        guard phase == .active || phase == .paused else { return }
        refreshElapsed()
        phase = .finishing
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        activePeriodStartedAt = nil
        publishWidgetSnapshot(forceReload: true)
        let finalElapsed = elapsed
        let finalHeartRate = heartRate
        Task {
            do {
                let completion = try await workout.finish()
                let finalDistance = completion.actualDistance
                queueCompletedRun(
                    completion: completion,
                    elapsed: finalElapsed,
                    distance: finalDistance
                )
                summary = Summary(
                    elapsed: finalElapsed,
                    actualDistance: finalDistance,
                    averagePace: averagePace(elapsed: finalElapsed, distance: finalDistance),
                    heartRate: finalHeartRate,
                    paceProgress: makePaceProgress(elapsed: finalElapsed, distance: finalDistance),
                    workoutSaved: completion.workoutSaved,
                    routeSaved: completion.routeSaved
                )
            } catch {
                let finalDistance = actualDistance
                summary = Summary(
                    elapsed: finalElapsed,
                    actualDistance: finalDistance,
                    averagePace: averagePace(elapsed: finalElapsed, distance: finalDistance),
                    heartRate: finalHeartRate,
                    paceProgress: makePaceProgress(elapsed: finalElapsed, distance: finalDistance),
                    workoutSaved: false,
                    routeSaved: false
                )
                errorMessage = "The run ended, but the workout could not be saved: \(error.localizedDescription)"
            }
            phase = .finished
            publishWidgetSnapshot(forceReload: true)
        }
    }

    private func queueCompletedRun(
        completion: WorkoutManager.Completion,
        elapsed: TimeInterval,
        distance: Double
    ) {
        let run = RecordedRun(
            name: runName,
            startedAt: completion.startedAt,
            endedAt: completion.endedAt,
            activeDuration: elapsed,
            distanceMeters: distance,
            points: completion.points
        )
        do { try WatchConnectivityManager.queueCompletedRun(run) }
        catch { errorMessage = "The run was saved to Health, but it could not be queued for Strava: \(error.localizedDescription)" }
    }

    private func refreshElapsed(playPaceHaptics: Bool = true) {
        handleWidgetCommand()
        guard phase == .active || phase == .paused else { return }
        elapsed = accumulatedElapsed + (activePeriodStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
        refreshPaceStatus(playHaptics: playPaceHaptics)
        publishWidgetSnapshot()
    }

    private func refreshPaceStatus(playHaptics: Bool) {
        guard let target = targetPaceSecondsPerKilometer,
              let progress = makePaceProgress(elapsed: elapsed, distance: actualDistance) else {
            paceProgress = nil
            isBehindPace = false
            return
        }
        paceProgress = progress
        guard !isOffCourse else { return }
        let event = paceAlertState.update(
            averagePace: progress.averagePaceSecondsPerKilometer,
            targetPace: target,
            distanceCompleted: actualDistance,
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

    var averagePace: Double? { averagePace(elapsed: elapsed, distance: actualDistance) }

    var isGuidedRun: Bool { route != nil }

    var runName: String { route?.name ?? "Free Run" }

    private func averagePace(elapsed: TimeInterval, distance: Double) -> Double? {
        guard elapsed.isFinite, elapsed >= 0, distance.isFinite, distance > 0 else { return nil }
        return elapsed / (distance / 1_000)
    }

    private func makePaceProgress(elapsed: TimeInterval, distance: Double) -> PaceProgress? {
        guard let target = targetPaceSecondsPerKilometer else { return nil }
        let plannedDistance = route.map {
            max(1, $0.totalDistance - (guidanceStartDistanceAlong ?? 0))
        } ?? max(1, distance)
        return PaceCalculator.progress(
            targetPaceSecondsPerKilometer: target,
            elapsed: elapsed,
            distanceCompleted: distance,
            plannedDistance: plannedDistance
        )
    }

    private func handleWidgetCommand() {
        guard let command = WorkoutWidgetStore.consumeCommand() else { return }
        switch command {
        case .pause where phase == .active: pause()
        case .resume where phase == .paused: resume()
        case .finish where phase == .active || phase == .paused: finish()
        default: break
        }
    }

    private func publishWidgetSnapshot(forceReload: Bool = false) {
        let widgetPhase: WorkoutWidgetStore.Phase
        switch phase {
        case .active: widgetPhase = .active
        case .paused: widgetPhase = .paused
        case .finishing: widgetPhase = .finishing
        case .ready, .starting, .finished: widgetPhase = .inactive
        }
        WorkoutWidgetStore.writeSnapshot(.init(
            phase: widgetPhase,
            runName: runName,
            elapsed: elapsed,
            distance: actualDistance,
            averagePace: averagePace,
            updatedAt: .now
        ))
        guard forceReload || Date().timeIntervalSince(lastWidgetReload) >= 15 else { return }
        lastWidgetReload = .now
        WidgetCenter.shared.reloadTimelines(ofKind: WorkoutWidgetStore.widgetKind)
    }

    deinit {
        timer?.invalidate()
        startTask?.cancel()
        startTimeoutTask?.cancel()
    }
}

extension RouteNavigationModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            guard phase == .active, latest.timestamp.timeIntervalSinceNow > -15 else { return }
            location = latest
            workout.addActualLocation(latest)
            guard var matcher else {
                refreshElapsed(playPaceHaptics: false)
                return
            }
            do {
                let value = try matcher.match(
                    latitude: latest.coordinate.latitude,
                    longitude: latest.coordinate.longitude,
                    horizontalAccuracy: latest.horizontalAccuracy
                )
                self.matcher = matcher
                match = value
                if guidanceStartDistanceAlong == nil { guidanceStartDistanceAlong = value.distanceAlongRoute }
                routeDistanceCompleted = max(
                    routeDistanceCompleted,
                    max(0, value.distanceAlongRoute - (guidanceStartDistanceAlong ?? value.distanceAlongRoute))
                )
                let alertEvent = alertState.update(distance: value.distanceFromRoute)
                isOffCourse = alertState.isOffCourse
                switch alertEvent {
                case .wentOffCourse, .repeatWarning: WKInterfaceDevice.current().play(.retry)
                case .returnedToRoute: WKInterfaceDevice.current().play(.success)
                case .none: break
                }
                let reachedFinish = !didSignalFinish
                    && value.progress > 0.98
                    && (route?.totalDistance ?? 0) - value.distanceAlongRoute < 25
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
        // Core Location reports this transiently while it is still acquiring a
        // fix. Turning it into an alert interrupts guidance even though tracking
        // normally resumes on the next sample.
        if let locationError = error as? CLError, locationError.code == .locationUnknown { return }
        Task { @MainActor in errorMessage = "Location is unavailable: \(error.localizedDescription)" }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedAlways || status == .authorizedWhenInUse, awaitingLocationAuthorization {
                awaitingLocationAuthorization = false
                if let startAttemptID { beginWorkout(for: startAttemptID) }
            } else if status == .denied || status == .restricted {
                awaitingLocationAuthorization = false
                if let startAttemptID {
                    failStart(attemptID: startAttemptID, message: "Location permission is required to track an outdoor run.")
                }
            }
        }
    }
}
