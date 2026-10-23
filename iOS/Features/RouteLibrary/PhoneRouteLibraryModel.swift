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
    @Published private(set) var areRoutesReady = false
    @Published private(set) var areRunsReady = false
    /// Bumps when saved runs change so analytics can reuse an unchanged snapshot.
    @Published private(set) var contentRevision = 0
    @Published var errorMessage: String?
    @Published var storageWarning: String?
    let connectivity: PhoneConnectivityManager
    let strava: StravaManager
    let health: RunningHealthStore
    /// Holds the last analytics snapshot. It is not published, so filling it does not redraw the shell.
    let analyticsScreenStore = AnalyticsScreenStore()
    let runStore: RecordedRunFileStore
    private var connectivityCancellable: AnyCancellable?
    private let importer = GPXImportService()
    private let store: RouteFileStore
    private var routeGeneration = 0
    private var runGeneration = 0
    private var routeWarning: String?
    private var runWarning: String?

    init() {
        let base = (try? GPXImportService.applicationSupportDirectory()) ?? FileManager.default.temporaryDirectory
        store = RouteFileStore(directory: base.appendingPathComponent("Routes", isDirectory: true))
        runStore = RecordedRunFileStore(directory: base.appendingPathComponent("CompletedRuns", isDirectory: true))
        connectivity = PhoneConnectivityManager(runStore: runStore)
        strava = StravaManager(runStore: runStore)
        health = RunningHealthStore()
        connectivityCancellable = connectivity.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        connectivity.onCompletedRunReceived = { [weak self] _ in
            self?.reloadCompletedRuns()
        }
        Task { await self.loadInitialLibrary() }
    }

    func syncWatchAppearance(preference: AppAppearance, resolved: ResolvedAppearance) {
        connectivity.syncAppearance(preference: preference, resolved: resolved)
    }

    func handleIncomingURL(_ url: URL) {
        if !strava.handleIncomingURL(url) { importRoute(from: url) }
    }

    func reloadCompletedRuns() {
        let generation = beginRunLoad()
        Task { await self.reloadRuns(generation: generation) }
    }

    func delete(_ run: RecordedRun) {
        do {
            try runStore.delete(run)
            completedRuns.removeAll { $0.id == run.id }
            strava.updateLocalStatuses(for: completedRuns)
            contentRevision += 1
            let generation = beginRunLoad()
            Task { await self.reloadRuns(generation: generation) }
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
        let store = self.store
        Task {
            defer { isImporting = false }
            do {
                let route = try await Task.detached(priority: .userInitiated) {
                    try importer.importRoute(from: url)
                }.value
                do { try store.save(route) }
                catch { importer.removeProvenance(for: route); throw error }
                let generation = beginRouteLoad()
                await reloadRoutes(generation: generation)
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
            routes.removeAll { $0.id == route.id }
            let generation = beginRouteLoad()
            Task { await self.reloadRoutes(generation: generation) }
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
            let generation = beginRouteLoad()
            Task { await self.reloadRoutes(generation: generation) }
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
            let generation = beginRouteLoad()
            Task { await self.reloadRoutes(generation: generation) }
        } catch {
            phoneLibraryLogger.error("Target pace save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func loadInitialLibrary() async {
        await seedBundledRouteIfNeeded()
        let routeToken = beginRouteLoad()
        let runToken = beginRunLoad()
        async let loadedRoutes: Void = reloadRoutes(generation: routeToken)
        async let loadedRuns: Void = reloadRuns(generation: runToken)
        _ = await (loadedRoutes, loadedRuns)
    }

    private func seedBundledRouteIfNeeded() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.bundledRouteSeedKey),
              let url = Bundle.main.url(forResource: "DefaultRoute", withExtension: "gpx") else { return }
        let store = store
        let result = await Task.detached(priority: .userInitiated) {
            PhoneLibrarySeed.install(from: url, into: store)
        }.value
        switch result {
        case .seeded, .alreadyPresent:
            defaults.set(true, forKey: Self.bundledRouteSeedKey)
        case .failed(let message):
            errorMessage = "The bundled test route could not be installed: \(message)"
        }
    }

    private func beginRouteLoad() -> Int {
        routeGeneration += 1
        return routeGeneration
    }

    private func beginRunLoad() -> Int {
        runGeneration += 1
        return runGeneration
    }

    private func reloadRoutes(generation: Int) async {
        let store = store
        let result = await Task.detached(priority: .userInitiated) {
            store.loadAll()
        }.value
        guard generation == routeGeneration else { return }
        routes = result.routes
        routeWarning = result.issues.isEmpty ? nil : "Skipped \(result.issues.count) damaged route file(s)."
        publishWarning()
        areRoutesReady = true
    }

    private func reloadRuns(generation: Int) async {
        let runStore = runStore
        let result = await Task.detached(priority: .userInitiated) {
            runStore.loadAll()
        }.value
        guard generation == runGeneration else { return }
        completedRuns = result.runs
        runWarning = result.issues.isEmpty ? nil : "Skipped \(result.issues.count) damaged completed run file(s)."
        publishWarning()
        strava.updateLocalStatuses(for: completedRuns)
        contentRevision += 1
        areRunsReady = true
    }

    private func publishWarning() {
        storageWarning = runWarning ?? routeWarning
    }
}

private enum PhoneLibrarySeed {
    static func install(from url: URL, into store: RouteFileStore) -> PhoneSeedResult {
        do {
            var route = try GPXParser().parse(url: url)
            route.name = "Spartacus 2025 – Terep XL"
            try store.save(route)
            return .seeded
        } catch RouteStoreError.duplicateRoute {
            return .alreadyPresent
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

private enum PhoneSeedResult: Sendable {
    case seeded
    case alreadyPresent
    case failed(String)
}
