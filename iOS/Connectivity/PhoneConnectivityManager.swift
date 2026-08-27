import Combine
import Foundation
import OSLog
import RouteLatchCore
import WatchConnectivity

private let phoneConnectivityLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RouteLatch", category: "WatchConnectivity")

enum RouteTransferStatus: Equatable {
    case notSent, connecting, unavailable(String), preparing, queued, transferring, delivered, failed(String)

    var label: String {
        switch self {
        case .notSent: "Not sent"
        case .connecting: "Connecting to Apple Watch"
        case .unavailable(let reason): reason
        case .preparing: "Preparing route for Watch"
        case .queued: "Queued for Watch"
        case .transferring: "Transferred; awaiting Watch receipt"
        case .delivered: "Available on Apple Watch"
        case .failed(let reason): "Transfer failed: \(reason)"
        }
    }
}

@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var statuses: [UUID: RouteTransferStatus] = [:]
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private var pendingRoutes: [UUID: Route] = [:]
    private var preparingRouteIDs: Set<UUID> = []

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func status(for route: Route) -> RouteTransferStatus { statuses[route.id] ?? .notSent }

    func markRouteChanged(_ routeID: UUID) {
        pendingRoutes.removeValue(forKey: routeID)
        statuses[routeID] = .notSent
    }

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
        guard preparingRouteIDs.insert(route.id).inserted else { return }
        statuses[route.id] = .preparing
        Task {
            defer { preparingRouteIDs.remove(route.id) }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try RouteTransferCodec.encode(RouteSimplifier.simplifyForWatch(route))
                }.value
                guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else {
                    statuses[route.id] = .unavailable("Apple Watch became unavailable")
                    return
                }
                let filename = "RouteLatch-\(route.id.uuidString)-\(UUID().uuidString).route"
                let outgoing = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try data.write(to: outgoing, options: .atomic)
                session.transferFile(outgoing, metadata: [
                    "routeID": route.id.uuidString,
                    "name": route.name,
                    "schemaVersion": Route.currentSchemaVersion
                ])
                pendingRoutes.removeValue(forKey: route.id)
                statuses[route.id] = .queued
            } catch {
                pendingRoutes.removeValue(forKey: route.id)
                phoneConnectivityLogger.error("Could not queue route transfer: \(error.localizedDescription, privacy: .public)")
                statuses[route.id] = .failed(error.localizedDescription)
            }
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
            if let errorMessage { phoneConnectivityLogger.error("Route transfer failed: \(errorMessage, privacy: .public)") }
            if let routeID { statuses[routeID] = errorMessage.map(RouteTransferStatus.failed) ?? .transferring }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let value = userInfo["routeReceiptID"] as? String,
              let routeID = UUID(uuidString: value) else { return }
        let receiptError = userInfo["routeReceiptError"] as? String
        Task { @MainActor in
            statuses[routeID] = receiptError.map(RouteTransferStatus.failed) ?? .delivered
        }
    }
}
