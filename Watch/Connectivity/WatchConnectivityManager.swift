import Foundation
import OSLog
import RouteLatchCore
import WatchConnectivity

private let watchConnectivityLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RouteLatch", category: "WatchConnectivity")

@MainActor
final class WatchConnectivityManager: NSObject {
    private static weak var shared: WatchConnectivityManager?
    var onRouteReceived: (() -> Void)?
    var onTransferError: ((String) -> Void)?
    private let store: RouteFileStore
    private let runStore: RecordedRunFileStore
    private var transferringRunIDs: Set<UUID> = []

    init(store: RouteFileStore, runStore: RecordedRunFileStore) {
        self.store = store
        self.runStore = runStore
        super.init()
        Self.shared = self
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
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
        Task { @MainActor [weak self] in
            if let error { self?.onTransferError?(error.localizedDescription) }
            else { self?.transferPendingRuns(using: .default) }
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
