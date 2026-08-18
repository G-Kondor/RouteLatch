import Foundation

public struct RouteLoadIssue: Identifiable, Sendable {
    public let id = UUID()
    public let filename: String
    public let message: String
}

public struct RouteLoadResult: Sendable {
    public let routes: [Route]
    public let issues: [RouteLoadIssue]
}

public enum RouteStoreError: Error, LocalizedError, Equatable, Sendable {
    case duplicateRoute
    public var errorDescription: String? { "This GPX course has already been imported." }
}

public struct RouteFileStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func loadAll() -> RouteLoadResult {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch {
            return RouteLoadResult(routes: [], issues: [RouteLoadIssue(filename: directory.lastPathComponent, message: error.localizedDescription)])
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var routes: [Route] = [], issues: [RouteLoadIssue] = []
        for file in files where file.pathExtension == "route" {
            do { routes.append(try RouteTransferCodec.decode(Data(contentsOf: file))) }
            catch { issues.append(RouteLoadIssue(filename: file.lastPathComponent, message: error.localizedDescription)) }
        }
        return RouteLoadResult(routes: routes.sorted { $0.importDate > $1.importDate }, issues: issues)
    }

    public func save(_ route: Route) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let fingerprint = route.sourceFingerprint,
           loadAll().routes.contains(where: { $0.id != route.id && $0.sourceFingerprint == fingerprint }) {
            throw RouteStoreError.duplicateRoute
        }
        try RouteTransferCodec.encode(route).write(to: url(for: route.id), options: .atomic)
    }

    public func delete(_ route: Route) throws { try FileManager.default.removeItem(at: url(for: route.id)) }
    public func url(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("route") }
}
