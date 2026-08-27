import Foundation

/// Produces a route-safe rendering/matching copy by simplifying every GPX segment independently.
/// A 3 m tolerance is deliberately small relative to RouteLatch's 40 m off-course threshold.
public enum RouteSimplifier {
    public static func simplifyForWatch(
        _ route: Route,
        maximumPointCount: Int = 20_000,
        maximumTolerance: Double = 12
    ) throws -> Route {
        guard route.pointCount > maximumPointCount else { return route }
        var tolerance = 3.0
        while tolerance <= maximumTolerance {
            let candidate = try simplify(route, tolerance: tolerance)
            if candidate.pointCount <= maximumPointCount { return candidate }
            tolerance *= 2
        }
        throw RouteSimplificationError.tooDetailedForWatch
    }

    public static func simplify(_ route: Route, tolerance: Double = 3) throws -> Route {
        guard tolerance > 0 else { return route }
        let segments = route.segments.map { RouteSegment(points: simplify($0.points, tolerance: tolerance)) }
        return try Route(
            id: route.id,
            name: route.name,
            originalFilename: route.originalFilename,
            importDate: route.importDate,
            segments: segments,
            sourceFingerprint: route.sourceFingerprint,
            targetPaceSecondsPerKilometer: route.targetPaceSecondsPerKilometer,
            schemaVersion: route.schemaVersion
        )
    }

    private static func simplify(_ points: [RoutePoint], tolerance: Double) -> [RoutePoint] {
        guard points.count > 2 else { return points }
        // Bounded windows avoid RDP's pathological quadratic behavior on adversarial 100k-point inputs.
        let maximumWindowEdges = 512
        if points.count > maximumWindowEdges + 1 {
            var result: [RoutePoint] = []
            var start = 0
            while start < points.count - 1 {
                let end = min(points.count - 1, start + maximumWindowEdges)
                let window = simplifyWindow(Array(points[start...end]), tolerance: tolerance)
                if result.isEmpty { result.append(contentsOf: window) }
                else { result.append(contentsOf: window.dropFirst()) }
                start = end
            }
            return result
        }
        return simplifyWindow(points, tolerance: tolerance)
    }

    private static func simplifyWindow(_ points: [RoutePoint], tolerance: Double) -> [RoutePoint] {
        var kept = [Bool](repeating: false, count: points.count)
        kept[0] = true
        kept[points.count - 1] = true
        var ranges = [(0, points.count - 1)]

        while let (start, end) = ranges.popLast() {
            guard end > start + 1 else { continue }
            var maximumDistance = 0.0
            var maximumIndex: Int?
            for index in (start + 1)..<end {
                let distance = perpendicularDistance(points[index], from: points[start], to: points[end])
                if distance > maximumDistance {
                    maximumDistance = distance
                    maximumIndex = index
                }
            }
            if maximumDistance > tolerance, let maximumIndex {
                kept[maximumIndex] = true
                ranges.append((start, maximumIndex))
                ranges.append((maximumIndex, end))
            }
        }

        return zip(points, kept).compactMap { $0.1 ? $0.0 : nil }
    }

    private static func perpendicularDistance(_ point: RoutePoint, from start: RoutePoint, to end: RoutePoint) -> Double {
        let referenceLatitude = (point.latitude + start.latitude + end.latitude) / 3 * .pi / 180
        let scaleX = 111_320.0 * max(0.000_001, abs(cos(referenceLatitude)))
        let scaleY = 110_574.0
        let bx = longitudeDelta(from: start.longitude, to: end.longitude) * scaleX
        let by = (end.latitude - start.latitude) * scaleY
        let px = longitudeDelta(from: start.longitude, to: point.longitude) * scaleX
        let py = (point.latitude - start.latitude) * scaleY
        let denominator = bx * bx + by * by
        guard denominator > 0 else { return hypot(px, py) }
        let fraction = max(0, min(1, (px * bx + py * by) / denominator))
        return hypot(px - fraction * bx, py - fraction * by)
    }

    private static func longitudeDelta(from start: Double, to end: Double) -> Double {
        var delta = end - start
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

public enum RouteSimplificationError: Error, LocalizedError, Equatable, Sendable {
    case tooDetailedForWatch

    public var errorDescription: String? {
        "This route remains too detailed for reliable Apple Watch guidance after safe simplification."
    }
}
