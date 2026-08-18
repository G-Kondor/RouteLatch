import Foundation

public struct RoutePoint: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let elevation: Double?
    public let timestamp: Date?

    public init(latitude: Double, longitude: Double, elevation: Double? = nil, timestamp: Date? = nil) throws {
        guard latitude.isFinite, (-90...90).contains(latitude) else { throw RouteValidationError.invalidLatitude(latitude) }
        guard longitude.isFinite, (-180...180).contains(longitude) else { throw RouteValidationError.invalidLongitude(longitude) }
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation?.isFinite == true ? elevation : nil
        self.timestamp = timestamp
    }
}

public struct RouteSegment: Codable, Hashable, Sendable {
    public var points: [RoutePoint]
    public init(points: [RoutePoint]) { self.points = points }
}

public struct RouteBounds: Codable, Hashable, Sendable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double

    public init(points: [RoutePoint]) {
        minLatitude = points.map(\.latitude).min() ?? 0
        maxLatitude = points.map(\.latitude).max() ?? 0
        minLongitude = points.map(\.longitude).min() ?? 0
        maxLongitude = points.map(\.longitude).max() ?? 0
    }
}

public struct Route: Codable, Identifiable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public var name: String
    public let originalFilename: String
    public let importDate: Date
    public let segments: [RouteSegment]
    public let totalDistance: Double
    public let totalAscent: Double?
    public let totalDescent: Double?
    public let start: RoutePoint
    public let finish: RoutePoint
    public let bounds: RouteBounds
    public let schemaVersion: Int
    public let sourceFingerprint: String?

    public var pointCount: Int { segments.reduce(0) { $0 + $1.points.count } }

    public init(
        id: UUID = UUID(), name: String, originalFilename: String, importDate: Date = .now,
        segments: [RouteSegment], sourceFingerprint: String? = nil, schemaVersion: Int = Self.currentSchemaVersion
    ) throws {
        let usable = segments.filter { !$0.points.isEmpty }
        guard let first = usable.first?.points.first, let last = usable.last?.points.last else {
            throw RouteValidationError.noUsablePoints
        }
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Route" : name
        self.originalFilename = originalFilename
        self.importDate = importDate
        self.segments = usable
        self.totalDistance = RouteMetrics.distance(of: usable)
        let elevation = RouteMetrics.elevation(of: usable)
        self.totalAscent = elevation.available ? elevation.ascent : nil
        self.totalDescent = elevation.available ? elevation.descent : nil
        self.start = first
        self.finish = last
        self.bounds = RouteBounds(points: usable.flatMap(\.points))
        self.schemaVersion = schemaVersion
        self.sourceFingerprint = sourceFingerprint
    }
}

public enum RouteValidationError: Error, LocalizedError, Equatable, Sendable {
    case invalidLatitude(Double)
    case invalidLongitude(Double)
    case noUsablePoints
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLatitude(let value): "Latitude \(value) is outside −90…90."
        case .invalidLongitude(let value): "Longitude \(value) is outside −180…180."
        case .noUsablePoints: "The file contains no usable route points."
        case .unsupportedSchema(let version): "Route schema version \(version) is not supported."
        }
    }
}

public enum RouteMetrics {
    public static func distance(of segments: [RouteSegment]) -> Double {
        segments.reduce(0) { total, segment in
            total + zip(segment.points, segment.points.dropFirst()).reduce(0) { $0 + haversine($1.0, $1.1) }
        }
    }

    public static func elevation(of segments: [RouteSegment]) -> (ascent: Double, descent: Double, available: Bool) {
        var ascent = 0.0, descent = 0.0, samples = 0
        for segment in segments {
            for (a, b) in zip(segment.points, segment.points.dropFirst()) {
                guard let first = a.elevation, let second = b.elevation else { continue }
                let delta = second - first
                if delta > 0 { ascent += delta } else { descent -= delta }
                samples += 1
            }
        }
        return (ascent, descent, samples > 0)
    }

    public static func haversine(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let radius = 6_371_008.8
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1, dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }
}
