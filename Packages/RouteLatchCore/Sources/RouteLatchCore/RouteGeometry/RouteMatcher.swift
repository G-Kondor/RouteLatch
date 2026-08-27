import Foundation

public struct RouteMatch: Equatable, Sendable {
    public let distanceFromRoute: Double
    public let distanceAlongRoute: Double
    public let progress: Double
    public let segmentIndex: Int
    public let edgeIndex: Int
    public let projectedLatitude: Double
    public let projectedLongitude: Double
}

public enum RouteMatchingError: Error, LocalizedError, Equatable, Sendable {
    case poorHorizontalAccuracy
    case noUsableEdges
    public var errorDescription: String? {
        switch self {
        case .poorHorizontalAccuracy: "Location accuracy is too poor for route matching."
        case .noUsableEdges: "The route has no usable line segments."
        }
    }
}

public struct RouteMatcher: Sendable {
    public var localSearchRadius = 80
    public var maximumHorizontalAccuracy = 75.0
    private var lastEdge: Int?
    private var lastDistanceAlong: Double?
    private let edges: [Edge]
    private let totalDistance: Double

    public init(route: Route) {
        var result: [Edge] = [], accumulated = 0.0
        for (segmentIndex, segment) in route.segments.enumerated() {
            for edgeIndex in 0..<max(0, segment.points.count - 1) {
                let start = segment.points[edgeIndex], end = segment.points[edgeIndex + 1]
                let length = RouteMetrics.haversine(start, end)
                result.append(Edge(segmentIndex: segmentIndex, edgeIndex: edgeIndex, start: start, end: end, baseDistance: accumulated, length: length))
                accumulated += length
            }
        }
        edges = result
        totalDistance = max(route.totalDistance, accumulated)
    }

    public mutating func match(latitude: Double, longitude: Double, horizontalAccuracy: Double) throws -> RouteMatch {
        guard horizontalAccuracy >= 0, horizontalAccuracy <= maximumHorizontalAccuracy else { throw RouteMatchingError.poorHorizontalAccuracy }
        guard !edges.isEmpty else { throw RouteMatchingError.noUsableEdges }
        let indices: Range<Int>
        if let lastEdge {
            indices = max(0, lastEdge - localSearchRadius)..<min(edges.count, lastEdge + localSearchRadius + 1)
        } else { indices = 0..<edges.count }
        var best = bestProjection(latitude: latitude, longitude: longitude, indices: indices)
        if best.distance > 150, indices.count < edges.count {
            best = bestProjection(latitude: latitude, longitude: longitude, indices: 0..<edges.count)
        }
        lastEdge = best.index
        let edge = edges[best.index]
        let along = min(totalDistance, edge.baseDistance + best.fraction * edge.length)
        lastDistanceAlong = along
        return RouteMatch(
            distanceFromRoute: best.distance, distanceAlongRoute: along,
            progress: totalDistance > 0 ? along / totalDistance : 0,
            segmentIndex: edge.segmentIndex, edgeIndex: edge.edgeIndex,
            projectedLatitude: best.latitude, projectedLongitude: best.longitude
        )
    }

    private func bestProjection(latitude: Double, longitude: Double, indices: Range<Int>) -> Projection {
        indices.reduce(Projection(index: indices.lowerBound, distance: .greatestFiniteMagnitude, fraction: 0, latitude: latitude, longitude: longitude)) { best, index in
            let candidate = project(latitude: latitude, longitude: longitude, edge: edges[index], index: index)
            guard abs(candidate.distance - best.distance) <= 2, let lastEdge else {
                return candidate.distance < best.distance ? candidate : best
            }
            if let lastDistanceAlong {
                let candidateAlong = edges[candidate.index].baseDistance + candidate.fraction * edges[candidate.index].length
                let bestAlong = edges[best.index].baseDistance + best.fraction * edges[best.index].length
                let candidateMovesForward = candidateAlong >= lastDistanceAlong - 3
                let bestMovesForward = bestAlong >= lastDistanceAlong - 3
                if candidateMovesForward != bestMovesForward { return candidateMovesForward ? candidate : best }
            }
            let candidateDelta = abs(candidate.index - lastEdge)
            let bestDelta = abs(best.index - lastEdge)
            if candidateDelta != bestDelta { return candidateDelta < bestDelta ? candidate : best }
            if candidate.index >= lastEdge, best.index < lastEdge { return candidate }
            return candidate.distance < best.distance ? candidate : best
        }
    }

    private func project(latitude: Double, longitude: Double, edge: Edge, index: Int) -> Projection {
        let referenceLatitude = (latitude + edge.start.latitude + edge.end.latitude) / 3 * .pi / 180
        let scaleX = 111_320.0 * max(0.000_001, abs(cos(referenceLatitude))), scaleY = 110_574.0
        let ax = 0.0, ay = edge.start.latitude * scaleY
        let bx = longitudeDelta(from: edge.start.longitude, to: edge.end.longitude) * scaleX
        let by = edge.end.latitude * scaleY
        let px = longitudeDelta(from: edge.start.longitude, to: longitude) * scaleX
        let py = latitude * scaleY
        let dx = bx - ax, dy = by - ay
        let denominator = dx * dx + dy * dy
        let fraction = denominator > 0 ? max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / denominator)) : 0
        let x = ax + fraction * dx, y = ay + fraction * dy
        let projectedLongitude = wrappedLongitude(edge.start.longitude + x / scaleX)
        return Projection(index: index, distance: hypot(px - x, py - y), fraction: fraction, latitude: y / scaleY, longitude: projectedLongitude)
    }

    private func longitudeDelta(from start: Double, to end: Double) -> Double {
        var delta = end - start
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private func wrappedLongitude(_ longitude: Double) -> Double {
        var result = longitude
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}

private struct Edge: Sendable {
    let segmentIndex: Int, edgeIndex: Int
    let start: RoutePoint, end: RoutePoint
    let baseDistance: Double, length: Double
}
private struct Projection { let index: Int; let distance: Double; let fraction: Double; let latitude: Double; let longitude: Double }

public struct OffCourseAlertState: Equatable, Sendable {
    public enum Event: Equatable, Sendable { case wentOffCourse, returnedToRoute, repeatWarning, none }
    public var enterThreshold = 40.0
    public var exitThreshold = 25.0
    public var cooldown: TimeInterval = 20
    public private(set) var isOffCourse = false
    private var lastWarning: Date?

    public init() {}

    public mutating func update(distance: Double, at date: Date = .now) -> Event {
        if !isOffCourse, distance > enterThreshold {
            isOffCourse = true; lastWarning = date; return .wentOffCourse
        }
        if isOffCourse, distance < exitThreshold {
            isOffCourse = false; return .returnedToRoute
        }
        if isOffCourse, let lastWarning, date.timeIntervalSince(lastWarning) >= cooldown {
            self.lastWarning = date; return .repeatWarning
        }
        return .none
    }
}
