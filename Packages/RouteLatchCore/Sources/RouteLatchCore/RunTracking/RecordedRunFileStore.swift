import Foundation

public struct RecordedRunLoadIssue: Identifiable, Sendable {
    public let id = UUID()
    public let filename: String
    public let message: String
}

public struct RecordedRunLoadResult: Sendable {
    public let runs: [RecordedRun]
    public let issues: [RecordedRunLoadIssue]
}

public struct RecordedRunFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func loadAll() -> RecordedRunLoadResult {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch {
            return RecordedRunLoadResult(
                runs: [],
                issues: [.init(filename: directory.lastPathComponent, message: error.localizedDescription)]
            )
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var runs: [RecordedRun] = []
        var issues: [RecordedRunLoadIssue] = []
        for file in files where file.pathExtension == "run" {
            do { runs.append(try RecordedRunCodec.decode(Data(contentsOf: file))) }
            catch { issues.append(.init(filename: file.lastPathComponent, message: error.localizedDescription)) }
        }
        return .init(runs: runs.sorted { $0.startedAt > $1.startedAt }, issues: issues)
    }

    public func save(_ run: RecordedRun) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try RecordedRunCodec.encode(run).write(to: url(for: run.id), options: .atomic)
        try TCXEncoder.encode(run).write(to: tcxURL(for: run.id), options: .atomic)
    }

    public func delete(_ run: RecordedRun) throws {
        let fileManager = FileManager.default
        let runURL = url(for: run.id)
        let exportURL = tcxURL(for: run.id)
        if fileManager.fileExists(atPath: runURL.path) { try fileManager.removeItem(at: runURL) }
        if fileManager.fileExists(atPath: exportURL.path) { try fileManager.removeItem(at: exportURL) }
    }

    public func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("run")
    }

    public func tcxURL(for id: UUID) -> URL {
        directory.appendingPathComponent("RouteLatch-\(id.uuidString)").appendingPathExtension("tcx")
    }
}
