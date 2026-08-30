import Foundation

public struct RecordedRunPoint: Codable, Equatable, Sendable {
    public let latitude: Double?
    public let longitude: Double?
    public let elevation: Double?
    public let timestamp: Date
    public let heartRate: Double?

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        elevation: Double? = nil,
        timestamp: Date,
        heartRate: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.timestamp = timestamp
        self.heartRate = heartRate
    }
}

public struct RecordedRun: Codable, Identifiable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public let schemaVersion: Int
    public let name: String
    public let startedAt: Date
    public let endedAt: Date
    public let activeDuration: TimeInterval
    public let distanceMeters: Double
    public let points: [RecordedRunPoint]

    public init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date,
        endedAt: Date,
        activeDuration: TimeInterval,
        distanceMeters: Double,
        points: [RecordedRunPoint],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Run" : name
        self.startedAt = startedAt
        self.endedAt = max(endedAt, startedAt)
        self.activeDuration = max(0, activeDuration.isFinite ? activeDuration : 0)
        self.distanceMeters = max(0, distanceMeters.isFinite ? distanceMeters : 0)
        self.points = points
            .filter { point in
                point.timestamp >= startedAt.addingTimeInterval(-10)
                    && point.timestamp <= endedAt.addingTimeInterval(10)
                    && point.latitude.map { $0.isFinite && (-90...90).contains($0) } ?? true
                    && point.longitude.map { $0.isFinite && (-180...180).contains($0) } ?? true
            }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

public struct RecordedRunTransferEnvelope: Codable, Sendable {
    public let schemaVersion: Int
    public let run: RecordedRun

    public init(run: RecordedRun) {
        schemaVersion = RecordedRun.currentSchemaVersion
        self.run = run
    }
}

public enum RecordedRunCodec {
    public static let maximumEncodedSize = 100 * 1_024 * 1_024

    public static func encode(_ run: RecordedRun) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(RecordedRunTransferEnvelope(run: run))
    }

    public static func decode(_ data: Data) throws -> RecordedRun {
        guard data.count <= maximumEncodedSize else { throw RecordedRunError.payloadTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(RecordedRunTransferEnvelope.self, from: data)
        guard envelope.schemaVersion == RecordedRun.currentSchemaVersion,
              envelope.run.schemaVersion == RecordedRun.currentSchemaVersion else {
            throw RecordedRunError.unsupportedSchema(envelope.schemaVersion)
        }
        guard envelope.run.points.count <= 250_000 else { throw RecordedRunError.tooManyPoints }
        return RecordedRun(
            id: envelope.run.id,
            name: envelope.run.name,
            startedAt: envelope.run.startedAt,
            endedAt: envelope.run.endedAt,
            activeDuration: envelope.run.activeDuration,
            distanceMeters: envelope.run.distanceMeters,
            points: envelope.run.points,
            schemaVersion: envelope.run.schemaVersion
        )
    }
}

public enum RecordedRunError: Error, LocalizedError, Equatable, Sendable {
    case payloadTooLarge
    case tooManyPoints
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge: "The completed run is too large to transfer."
        case .tooManyPoints: "The completed run contains too many GPS points."
        case .unsupportedSchema(let version): "Run schema version \(version) is not supported."
        }
    }
}
