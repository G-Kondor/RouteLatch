import Foundation
import OSLog
import RouteLatchCore
import WatchConnectivity
import WidgetKit

private let watchConnectivityLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RouteLatch", category: "WatchConnectivity")

@MainActor
final class WatchConnectivityManager: NSObject {
    private static weak var shared: WatchConnectivityManager?
    var onRouteReceived: (() -> Void)?
    var onTransferError: ((String) -> Void)?
    var onAppearanceReceived: ((AppearanceSnapshot) -> Void)?
    private(set) var appearance: AppearanceSnapshot?
    private let store: RouteFileStore
    private let runStore: RecordedRunFileStore
    private var transferringRunIDs: Set<UUID> = []

    init(store: RouteFileStore, runStore: RecordedRunFileStore) {
        self.store = store
        self.runStore = runStore
        super.init()
        Self.shared = self
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func applyReceivedAppearance() {
        guard WCSession.isSupported() else { return }
        guard let snapshot = AppearanceSync.snapshot(from: WCSession.default.receivedApplicationContext) else { return }
        publishAppearance(snapshot)
    }

    func requestAppearanceFromPhone() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([AppearanceSync.requestKey: "1"], replyHandler: nil) { error in
            watchConnectivityLogger.error("Could not ask iPhone for the appearance: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func queueCompletedRun(_ run: RecordedRun) throws {
        guard let shared else { throw WatchConnectivityError.notReady }
        try shared.runStore.save(run)
        shared.transferPendingRuns(using: .default)
    }

    private func transferPendingRuns(using session: WCSession) {
        guard session.activationState == .activated else {
            session.activate()
            return
        }
        for run in runStore.loadAll().runs where !transferringRunIDs.contains(run.id) {
            transferringRunIDs.insert(run.id)
            session.transferFile(runStore.url(for: run.id), metadata: [
                "transferKind": "completedRun",
                "completedRunID": run.id.uuidString,
                "name": run.name,
                "schemaVersion": RecordedRun.currentSchemaVersion
            ])
        }
    }
}

private enum WatchConnectivityError: Error, LocalizedError {
    case notReady
    var errorDescription: String? { "The iPhone transfer service is not ready yet." }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let snapshot = AppearanceSync.snapshot(from: session.receivedApplicationContext)
        Task { @MainActor [weak self] in
            if let error { self?.onTransferError?(error.localizedDescription) }
            else { self?.transferPendingRuns(using: .default) }
            if let snapshot { self?.publishAppearance(snapshot) }
            self?.requestAppearanceFromPhone()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = AppearanceSync.snapshot(from: applicationContext) else { return }
        Task { @MainActor [weak self] in
            self?.publishAppearance(snapshot)
        }
    }

    private func publishAppearance(_ snapshot: AppearanceSnapshot) {
        let changed = appearance != snapshot
        appearance = snapshot
        WorkoutWidgetStore.writeResolvedAppearance(snapshot.resolved.rawValue)
        if changed {
            WidgetCenter.shared.reloadTimelines(ofKind: WorkoutWidgetStore.widgetKind)
        }
        onAppearanceReceived?(snapshot)
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let snapshot = AppearanceSync.snapshot(from: session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            if let snapshot { self?.publishAppearance(snapshot) }
            if reachable { self?.requestAppearanceFromPhone() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let snapshot = AppearanceSync.snapshot(from: message) else { return }
        Task { @MainActor [weak self] in
            self?.publishAppearance(snapshot)
        }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        do {
            let data = try Data(contentsOf: file.fileURL)
            let route = try RouteTransferCodec.decode(data)
            try store.save(route)
            session.transferUserInfo(["routeReceiptID": route.id.uuidString])
            Task { @MainActor in onRouteReceived?() }
        } catch {
            watchConnectivityLogger.error("Received route could not be stored: \(error.localizedDescription, privacy: .public)")
            let routeID = file.metadata?["routeID"] as? String
            if let routeID {
                session.transferUserInfo(["routeReceiptID": routeID, "routeReceiptError": error.localizedDescription])
            }
            Task { @MainActor in onTransferError?(error.localizedDescription) }
        }
    }

    nonisolated func session(_ session: WCSession, transfer fileTransfer: WCSessionFileTransfer, didFinish error: Error?) {
        let runID = (fileTransfer.file.metadata?["completedRunID"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor [weak self] in
            if let runID { self?.transferringRunIDs.remove(runID) }
            if let error { self?.onTransferError?("The completed run could not be sent to iPhone: \(error.localizedDescription)") }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let value = userInfo["completedRunReceiptID"] as? String,
              let runID = UUID(uuidString: value) else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  let run = runStore.loadAll().runs.first(where: { $0.id == runID }) else { return }
            try? runStore.delete(run)
            transferringRunIDs.remove(runID)
        }
    }
}
