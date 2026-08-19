import Combine
import Foundation
import RouteLatchCore
import WatchConnectivity

enum RouteTransferStatus: Equatable {
    case notSent, connecting, unavailable(String), queued, delivered, failed(String)

    var label: String {
        switch self {
        case .notSent: "Not sent"
        case .connecting: "Connecting to Apple Watch"
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
    private var pendingRoutes: [UUID: Route] = [:]

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func status(for route: Route) -> RouteTransferStatus { statuses[route.id] ?? .notSent }

    func send(_ route: Route) {
        guard let session else { statuses[route.id] = .unavailable("WatchConnectivity unavailable"); return }
        pendingRoutes[route.id] = route
        guard session.activationState == .activated else {
            statuses[route.id] = .connecting
            session.activate()
            return
        }
        transferPendingRoute(route, using: session)
    }

    private func transferPendingRoute(_ route: Route, using session: WCSession) {
        guard session.isPaired else {
            pendingRoutes.removeValue(forKey: route.id)
            statuses[route.id] = .unavailable("No paired Apple Watch")
            return
        }
        guard session.isWatchAppInstalled else {
            statuses[route.id] = .unavailable("Watch app not installed yet")
            return
        }
        do {
            let outgoing = FileManager.default.temporaryDirectory.appendingPathComponent(route.id.uuidString).appendingPathExtension("route")
            try RouteTransferCodec.encode(route).write(to: outgoing, options: .atomic)
            let transfer = session.transferFile(outgoing, metadata: ["routeID": route.id.uuidString, "name": route.name, "schemaVersion": Route.currentSchemaVersion])
            _ = transfer
            pendingRoutes.removeValue(forKey: route.id)
            statuses[route.id] = .queued
        } catch {
            pendingRoutes.removeValue(forKey: route.id)
            statuses[route.id] = .failed(error.localizedDescription)
        }
    }

    private func refreshWatchState(activationError: String? = nil) {
        guard let session else { return }
        if let activationError {
            for route in pendingRoutes.values { statuses[route.id] = .failed(activationError) }
            pendingRoutes.removeAll()
            return
        }
        guard session.activationState == .activated else { return }
        let routes = Array(pendingRoutes.values)
        for route in routes { transferPendingRoute(route, using: session) }
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let errorMessage = error?.localizedDescription
        Task { @MainActor [weak self] in self?.refreshWatchState(activationError: errorMessage) }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refreshWatchState() }
    }
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
