import Combine
import Foundation
import RouteLatchCore

@MainActor
final class WatchRouteLibraryModel: ObservableObject {
    private static let bundledRouteSeedKey = "BundledRoute.Spartacus2025XL.v1.seeded"
    private static let freeRunTargetPaceKey = "FreeRun.TargetPaceSecondsPerKilometer"
    @Published private(set) var routes: [Route] = []
    @Published private(set) var isLoadingRoutes = true
    @Published private(set) var freeRunTargetPaceSecondsPerKilometer: Double?
    @Published var errorMessage: String?
    let store: RouteFileStore
    let runStore: RecordedRunFileStore
    private var connectivity: WatchConnectivityManager!

    init() {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        store = RouteFileStore(directory: support.appendingPathComponent("RouteLatch/Routes", isDirectory: true))
        runStore = RecordedRunFileStore(directory: support.appendingPathComponent("RouteLatch/PendingRuns", isDirectory: true))
        let storedPace = (UserDefaults.standard.object(forKey: Self.freeRunTargetPaceKey) as? NSNumber)?.doubleValue
        freeRunTargetPaceSecondsPerKilometer = storedPace.flatMap { PaceGoalConfiguration.isValid($0) ? $0 : nil }
        connectivity = WatchConnectivityManager(store: store, runStore: runStore)
        connectivity.onRouteReceived = { [weak self] in self?.reload() }
        connectivity.onTransferError = { [weak self] message in self?.errorMessage = "A route could not be received: \(message)" }
        Task { [weak self] in
            await self?.loadInitialRoutes()
        }
    }

    private func loadInitialRoutes() async {
        await seedBundledRouteIfNeeded()
        await loadRoutesFromDisk()
    }

    private func seedBundledRouteIfNeeded() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.bundledRouteSeedKey),
              let url = Bundle.main.url(forResource: "DefaultRoute", withExtension: "gpx") else { return }
        let store = store
        let result = await Task.detached(priority: .utility) {
            do {
                var route = try GPXParser().parse(url: url)
                route.name = "Spartacus 2025 – Terep XL"
                try store.save(route)
                return SeedResult.seeded
            } catch RouteStoreError.duplicateRoute {
                return SeedResult.alreadyPresent
            } catch {
                return SeedResult.failed(error.localizedDescription)
            }
        }.value

        switch result {
        case .seeded, .alreadyPresent:
            defaults.set(true, forKey: Self.bundledRouteSeedKey)
        case let .failed(message):
            errorMessage = "The bundled test route could not be installed: \(message)"
        }
    }

    func reload() {
        Task { [weak self] in
            await self?.loadRoutesFromDisk()
        }
    }

    private func loadRoutesFromDisk() async {
        let store = store
        let result = await Task.detached(priority: .userInitiated) {
            store.loadAll()
        }.value
        routes = result.routes
        isLoadingRoutes = false
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

    func setFreeRunTargetPace(_ secondsPerKilometer: Double?) {
        guard secondsPerKilometer.map(PaceGoalConfiguration.isValid) ?? true else { return }
        freeRunTargetPaceSecondsPerKilometer = secondsPerKilometer
        if let secondsPerKilometer {
            UserDefaults.standard.set(secondsPerKilometer, forKey: Self.freeRunTargetPaceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.freeRunTargetPaceKey)
        }
    }
}

private enum SeedResult: Sendable {
    case seeded
    case alreadyPresent
    case failed(String)
}
