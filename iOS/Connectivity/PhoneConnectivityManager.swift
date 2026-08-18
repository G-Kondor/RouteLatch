import Combine
import Foundation
import RouteLatchCore
import WatchConnectivity

enum RouteTransferStatus: Equatable {
    case notSent, unavailable(String), queued, delivered, failed(String)

    var label: String {
        switch self {
        case .notSent: "Not sent"
        case .unavailable(let reason): reason
        case .queued: "Queued for Watch"
        case .delivered: "Delivered"
        case .failed: "Transfer failed"
        }
    }
}

@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var statuses: [UUID: RouteTransferStatus] = [:]
    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func status(for route: Route) -> RouteTransferStatus { statuses[route.id] ?? .notSent }

    func send(_ route: Route) {
        guard let session else { statuses[route.id] = .unavailable("WatchConnectivity unavailable"); return }
        guard session.isPaired else { statuses[route.id] = .unavailable("No paired Apple Watch"); return }
        guard session.isWatchAppInstalled else { statuses[route.id] = .unavailable("Watch app not installed"); return }
        do {
            let outgoing = FileManager.default.temporaryDirectory.appendingPathComponent(route.id.uuidString).appendingPathExtension("route")
            try RouteTransferCodec.encode(route).write(to: outgoing, options: .atomic)
            let transfer = session.transferFile(outgoing, metadata: ["routeID": route.id.uuidString, "name": route.name, "schemaVersion": Route.currentSchemaVersion])
            _ = transfer
            statuses[route.id] = .queued
        } catch { statuses[route.id] = .failed(error.localizedDescription) }
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, transfer fileTransfer: WCSessionFileTransfer, didFinish error: Error?) {
        let routeID = (fileTransfer.file.metadata?["routeID"] as? String).flatMap(UUID.init(uuidString:))
        let fileURL = fileTransfer.file.fileURL
        let errorMessage = error?.localizedDescription
        Task { @MainActor in
            if let routeID { statuses[routeID] = errorMessage.map(RouteTransferStatus.failed) ?? .delivered }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
