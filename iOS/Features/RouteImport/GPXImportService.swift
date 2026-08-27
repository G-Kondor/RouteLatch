import Foundation
import RouteLatchCore

struct GPXImportService: Sendable {
    let parser = GPXParser()

    func importRoute(from externalURL: URL) throws -> Route {
        let secured = externalURL.startAccessingSecurityScopedResource()
        defer { if secured { externalURL.stopAccessingSecurityScopedResource() } }
        let originals = try Self.applicationSupportDirectory().appendingPathComponent("OriginalGPX", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let filename = externalURL.lastPathComponent.isEmpty ? "Imported.gpx" : externalURL.lastPathComponent
        let stagingDirectory = originals.appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        let copy = stagingDirectory.appendingPathComponent(filename)
        var shouldRemoveStaging = true
        defer { if shouldRemoveStaging { try? FileManager.default.removeItem(at: stagingDirectory) } }
        try FileManager.default.copyItem(at: externalURL, to: copy)
        let route = try parser.parse(url: copy)
        let destination = provenanceDirectory(for: route)
        try FileManager.default.moveItem(at: stagingDirectory, to: destination)
        shouldRemoveStaging = false
        return route
    }

    func removeProvenance(for route: Route) {
        try? FileManager.default.removeItem(at: provenanceDirectory(for: route))
    }

    private func provenanceDirectory(for route: Route) -> URL {
        let base = (try? Self.applicationSupportDirectory()) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("OriginalGPX/\(route.id.uuidString)", isDirectory: true)
    }

    static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("RouteLatch", isDirectory: true)
    }
}
