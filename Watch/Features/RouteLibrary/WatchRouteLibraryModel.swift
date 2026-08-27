import Combine
import Foundation
import RouteLatchCore

@MainActor
final class WatchRouteLibraryModel: ObservableObject {
    private static let bundledRouteSeedKey = "BundledRoute.Spartacus2025XL.v1.seeded"
    @Published private(set) var routes: [Route] = []
    @Published var errorMessage: String?
    let store: RouteFileStore
    private var connectivity: WatchConnectivityManager!

    init() {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        store = RouteFileStore(directory: support.appendingPathComponent("RouteLatch/Routes", isDirectory: true))
        seedBundledRouteIfNeeded()
        connectivity = WatchConnectivityManager(store: store)
        connectivity.onRouteReceived = { [weak self] in self?.reload() }
        connectivity.onTransferError = { [weak self] message in self?.errorMessage = "A route could not be received: \(message)" }
        reload()
    }

    private func seedBundledRouteIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.bundledRouteSeedKey),
              let url = Bundle.main.url(forResource: "DefaultRoute", withExtension: "gpx") else { return }
        do {
            var route = try GPXParser().parse(url: url)
            route.name = "Spartacus 2025 – Terep XL"
            try store.save(route)
            defaults.set(true, forKey: Self.bundledRouteSeedKey)
        } catch RouteStoreError.duplicateRoute {
            defaults.set(true, forKey: Self.bundledRouteSeedKey)
        } catch {
            errorMessage = "The bundled test route could not be installed: \(error.localizedDescription)"
        }
    }

    func reload() {
        let result = store.loadAll()
        routes = result.routes
        if !result.issues.isEmpty {
            errorMessage = "Skipped \(result.issues.count) damaged route file(s)."
        }
    }
    func delete(_ route: Route) {
        do { try store.delete(route); reload() } catch { errorMessage = error.localizedDescription }
    }

    func setTargetPace(_ secondsPerKilometer: Double?, for route: Route) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }),
              secondsPerKilometer.map(PaceGoalConfiguration.isValid) ?? true else { return }
        var updated = routes[index]
        updated.targetPaceSecondsPerKilometer = secondsPerKilometer
        do {
            try store.save(updated)
            routes[index] = updated
        } catch {
            errorMessage = "The target pace could not be saved: \(error.localizedDescription)"
        }
    }
}
