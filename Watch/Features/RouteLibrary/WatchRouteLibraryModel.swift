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

    func reload() { routes = store.loadAll().routes }
    func delete(_ route: Route) {
        do { try store.delete(route); reload() } catch { errorMessage = error.localizedDescription }
    }
}
