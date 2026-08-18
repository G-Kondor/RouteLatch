import Foundation
import RouteLatchCore
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject {
    var onRouteReceived: (() -> Void)?
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
            Task { @MainActor in onRouteReceived?() }
        } catch {
            // The temporary URL is consumed immediately. Corrupt or future-schema payloads are ignored safely.
        }
    }
}
