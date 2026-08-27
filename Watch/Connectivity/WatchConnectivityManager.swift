import Foundation
import OSLog
import RouteLatchCore
import WatchConnectivity

private let watchConnectivityLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RouteLatch", category: "WatchConnectivity")

@MainActor
final class WatchConnectivityManager: NSObject {
    var onRouteReceived: (() -> Void)?
    var onTransferError: ((String) -> Void)?
    private let store: RouteFileStore

    init(store: RouteFileStore) {
        self.store = store
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
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
}
