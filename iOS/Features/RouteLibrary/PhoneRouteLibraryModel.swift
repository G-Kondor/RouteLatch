import Combine
import Foundation
import OSLog
import RouteLatchCore

private let phoneLibraryLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RouteLatch", category: "RouteLibrary")

@MainActor
final class PhoneRouteLibraryModel: ObservableObject {
    private static let bundledRouteSeedKey = "BundledRoute.Spartacus2025XL.v1.seeded"
    @Published private(set) var routes: [Route] = []
    @Published private(set) var completedRuns: [RecordedRun] = []
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?
    @Published var storageWarning: String?
    let connectivity: PhoneConnectivityManager
    let strava: StravaManager
    let runStore: RecordedRunFileStore
    private var connectivityCancellable: AnyCancellable?
    private let importer = GPXImportService()
    private let store: RouteFileStore

    init() {
        let base = (try? GPXImportService.applicationSupportDirectory()) ?? FileManager.default.temporaryDirectory
        store = RouteFileStore(directory: base.appendingPathComponent("Routes", isDirectory: true))
        runStore = RecordedRunFileStore(directory: base.appendingPathComponent("CompletedRuns", isDirectory: true))
        connectivity = PhoneConnectivityManager(runStore: runStore)
        strava = StravaManager(runStore: runStore)
        connectivityCancellable = connectivity.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        connectivity.onCompletedRunReceived = { [weak self] _ in
            self?.reloadCompletedRuns()
        }
        seedBundledRouteIfNeeded()
        reload()
        reloadCompletedRuns()
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

    func handleIncomingURL(_ url: URL) {
        if !strava.handleIncomingURL(url) { importRoute(from: url) }
    }

    func reloadCompletedRuns() {
        let result = runStore.loadAll()
        completedRuns = result.runs
        if !result.issues.isEmpty {
            storageWarning = "Skipped \(result.issues.count) damaged completed run file(s)."
        }
        strava.updateLocalStatuses(for: completedRuns)
    }

    func delete(_ run: RecordedRun) {
        do {
            try runStore.delete(run)
            reloadCompletedRuns()
        } catch {
            phoneLibraryLogger.error("Completed run deletion failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func importRoute(from url: URL) {
        guard !isImporting else {
            errorMessage = "Another GPX import is already in progress."
            return
        }
        isImporting = true
        let importer = self.importer
        Task {
            defer { isImporting = false }
            do {
                let route = try await Task.detached(priority: .userInitiated) {
                    try importer.importRoute(from: url)
                }.value
                do { try store.save(route) }
                catch { importer.removeProvenance(for: route); throw error }
                reload()
            } catch {
                phoneLibraryLogger.error("Route import failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    func delete(_ route: Route) {
        do {
            try store.delete(route)
            importer.removeProvenance(for: route)
            reload()
        } catch {
            phoneLibraryLogger.error("Route deletion failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ route: Route, to name: String) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        var updated = route
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { return }
        do {
            try store.save(updated)
            routes[index] = updated
            connectivity.markRouteChanged(updated.id)
        }
        catch {
            phoneLibraryLogger.error("Route rename failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func setTargetPace(_ secondsPerKilometer: Double?, for route: Route) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        guard secondsPerKilometer.map(PaceGoalConfiguration.isValid) ?? true else {
            errorMessage = "Choose a target pace between 3:00 and 15:00 per kilometre."
            return
        }
        var updated = routes[index]
        updated.targetPaceSecondsPerKilometer = secondsPerKilometer
        do {
            try store.save(updated)
            routes[index] = updated
            connectivity.markRouteChanged(updated.id)
        } catch {
            phoneLibraryLogger.error("Target pace save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
