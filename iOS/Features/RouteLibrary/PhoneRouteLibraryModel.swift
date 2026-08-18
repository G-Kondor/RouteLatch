import Combine
import Foundation
import RouteLatchCore

@MainActor
final class PhoneRouteLibraryModel: ObservableObject {
    private static let bundledRouteSeedKey = "BundledRoute.Spartacus2025XL.v1.seeded"
    @Published private(set) var routes: [Route] = []
    @Published var errorMessage: String?
    @Published var storageWarning: String?
    let connectivity = PhoneConnectivityManager()
    private var connectivityCancellable: AnyCancellable?
    private let importer = GPXImportService()
    private lazy var store: RouteFileStore = {
        let base = (try? GPXImportService.applicationSupportDirectory()) ?? FileManager.default.temporaryDirectory
        return RouteFileStore(directory: base.appendingPathComponent("Routes", isDirectory: true))
    }()

    init() {
        connectivityCancellable = connectivity.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        seedBundledRouteIfNeeded()
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
        storageWarning = result.issues.isEmpty ? nil : "Skipped \(result.issues.count) damaged route file(s)."
    }

    func importRoute(from url: URL) {
        do { let route = try importer.importRoute(from: url); try store.save(route); reload() }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ route: Route) {
        do { try store.delete(route); reload() } catch { errorMessage = error.localizedDescription }
    }

    func rename(_ route: Route, to name: String) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        var updated = route
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { return }
        do { try store.save(updated); routes[index] = updated } catch { errorMessage = error.localizedDescription }
    }
}
