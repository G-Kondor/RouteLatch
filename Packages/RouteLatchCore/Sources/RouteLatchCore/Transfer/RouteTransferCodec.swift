import Foundation

public struct RouteTransferEnvelope: Codable, Sendable {
    public let schemaVersion: Int
    public let route: Route
    public init(route: Route) { self.schemaVersion = Route.currentSchemaVersion; self.route = route }
}

public enum RouteTransferCodec {
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
        guard envelope.schemaVersion == Route.currentSchemaVersion,
              envelope.route.schemaVersion == Route.currentSchemaVersion else {
            throw RouteValidationError.unsupportedSchema(envelope.schemaVersion)
        }
        return envelope.route
    }
}
