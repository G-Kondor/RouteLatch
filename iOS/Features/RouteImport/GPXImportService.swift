import Foundation
import RouteLatchCore

struct GPXImportService {
    let parser = GPXParser()

    func importRoute(from externalURL: URL) throws -> Route {
        let secured = externalURL.startAccessingSecurityScopedResource()
        defer { if secured { externalURL.stopAccessingSecurityScopedResource() } }
        let originals = try Self.applicationSupportDirectory().appendingPathComponent("OriginalGPX", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let filename = externalURL.lastPathComponent.isEmpty ? "Imported.gpx" : externalURL.lastPathComponent
        let copy = originals.appendingPathComponent(UUID().uuidString + "-" + filename)
        try FileManager.default.copyItem(at: externalURL, to: copy)
        do { return try parser.parse(url: copy) }
        catch { try? FileManager.default.removeItem(at: copy); throw error }
    }

    static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("RouteLatch", isDirectory: true)
    }
}
