import Combine
import CoreLocation
import Foundation
import RouteLatchCore
import WatchKit

@MainActor
final class RouteNavigationModel: NSObject, ObservableObject {
    enum Phase { case ready, active, paused, finished }
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var location: CLLocation?
    @Published private(set) var match: RouteMatch?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    let route: Route
    let workout = WorkoutManager()
    private let locationManager = CLLocationManager()
    private var matcher: RouteMatcher
    private var alertState = OffCourseAlertState()
    private var didSignalFinish = false
    private nonisolated(unsafe) var timer: Timer?
    private var startedAt: Date?

    init(route: Route) {
        self.route = route
        matcher = RouteMatcher(route: route)
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
    }

    func start() {
        Task {
            guard await workout.requestAuthorization() else { errorMessage = "Health access was denied. Reliable background workout tracking is unavailable."; return }
            do {
                try await workout.start()
                locationManager.requestWhenInUseAuthorization()
                locationManager.startUpdatingLocation()
                startedAt = .now
                phase = .active
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in guard let self, let startedAt = self.startedAt else { return }; self.elapsed = Date().timeIntervalSince(startedAt) }
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func pause() { phase = .paused; locationManager.stopUpdatingLocation(); workout.pause() }
    func resume() { phase = .active; locationManager.startUpdatingLocation(); workout.resume() }
    func finish() {
        phase = .finished; locationManager.stopUpdatingLocation(); timer?.invalidate()
        Task { await workout.finish() }
    }

    deinit { timer?.invalidate() }
}

extension RouteNavigationModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            guard phase == .active else { return }
            location = latest
            workout.addActualLocation(latest)
            do {
                let value = try matcher.match(latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude, horizontalAccuracy: latest.horizontalAccuracy)
                match = value
                switch alertState.update(distance: value.distanceFromRoute) {
                case .wentOffCourse, .repeatWarning: WKInterfaceDevice.current().play(.retry)
                case .returnedToRoute: WKInterfaceDevice.current().play(.success)
                case .none: break
                }
                if !didSignalFinish, route.totalDistance - value.distanceAlongRoute < 25 {
                    didSignalFinish = true
                    WKInterfaceDevice.current().play(.success)
                }
            } catch RouteMatchingError.poorHorizontalAccuracy { return }
            catch { errorMessage = error.localizedDescription }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { Task { @MainActor in errorMessage = error.localizedDescription } }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied { Task { @MainActor in errorMessage = "Location permission is required for route guidance." } }
    }
}
