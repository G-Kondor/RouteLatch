import Foundation

public struct RouteTransferEnvelope: Codable, Sendable {
    public let schemaVersion: Int
    public let route: Route
    public init(route: Route) { self.schemaVersion = Route.currentSchemaVersion; self.route = route }
}

public enum RouteTransferCodec {
    public static let maximumEncodedSize = 50 * 1_024 * 1_024

    public static func encode(_ route: Route) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode("bits:\(date.timeIntervalSinceReferenceDate.bitPattern)")
        }
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(RouteTransferEnvelope(route: route))
    }

    public static func decode(_ data: Data) throws -> Route {
        guard data.count <= maximumEncodedSize else { throw RouteTransferError.payloadTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let encoded = try? container.decode(String.self), encoded.hasPrefix("bits:"),
               let bits = UInt64(encoded.dropFirst(5)) {
                return Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
            }
            // Backward compatibility with early MVP files encoded as seconds since 1970.
            return Date(timeIntervalSince1970: try container.decode(Double.self))
        }
        let envelope = try decoder.decode(RouteTransferEnvelope.self, from: data)
        guard envelope.schemaVersion == Route.currentSchemaVersion else {
            throw RouteValidationError.unsupportedSchema(envelope.schemaVersion)
        }
        guard envelope.route.schemaVersion == Route.currentSchemaVersion else {
            throw RouteValidationError.unsupportedSchema(envelope.route.schemaVersion)
        }
        guard envelope.route.pointCount <= GPXParser.defaultMaximumPointCount else {
            throw RouteTransferError.tooManyPoints
        }
        return try Route(
            id: envelope.route.id,
            name: envelope.route.name,
            originalFilename: envelope.route.originalFilename,
            importDate: envelope.route.importDate,
            segments: envelope.route.segments,
            sourceFingerprint: envelope.route.sourceFingerprint,
            targetPaceSecondsPerKilometer: envelope.route.targetPaceSecondsPerKilometer,
            schemaVersion: envelope.route.schemaVersion
        )
    }
}

public enum RouteTransferError: Error, LocalizedError, Equatable, Sendable {
    case payloadTooLarge
    case tooManyPoints

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge: "The transferred route file is unreasonably large."
        case .tooManyPoints: "The transferred route exceeds the supported point limit."
        }
    }
}
