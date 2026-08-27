import Foundation
import XCTest
@testable import RouteLatchCore

final class RouteGeometryTests: XCTestCase {
    private func point(_ lat: Double, _ lon: Double) throws -> RoutePoint { try RoutePoint(latitude: lat, longitude: lon) }

    func testDistanceProjectionAndProgress() throws {
        let route = try Route(name: "Line", originalFilename: "line.gpx", segments: [.init(points: [point(0, 0), point(0, 0.001)])])
        XCTAssertEqual(route.totalDistance, 111.2, accuracy: 1)
        var matcher = RouteMatcher(route: route)
        let match = try matcher.match(latitude: 0.0001, longitude: 0.0005, horizontalAccuracy: 5)
        XCTAssertEqual(match.distanceFromRoute, 11.1, accuracy: 1)
        XCTAssertEqual(match.progress, 0.5, accuracy: 0.02)
    }

    func testDisconnectedSegmentsDoNotAddArtificialDistance() throws {
        let route = try Route(name: "Split", originalFilename: "split.gpx", segments: [
            .init(points: [point(0, 0), point(0, 0.001)]), .init(points: [point(1, 1), point(1, 1.001)])
        ])
        XCTAssertEqual(route.totalDistance, 222.4, accuracy: 2)
    }

    func testLoopAndStartNearFinishProgressesThroughSequentialEdges() throws {
        let loop = try Route(name: "Loop", originalFilename: "loop.gpx", segments: [.init(points: [point(0, 0), point(0, 0.001), point(0.001, 0.001), point(0.00001, 0.00001)])])
        var matcher = RouteMatcher(route: loop)
        let first = try matcher.match(latitude: 0, longitude: 0.0005, horizontalAccuracy: 5)
        let second = try matcher.match(latitude: 0.0005, longitude: 0.001, horizontalAccuracy: 5)
        let nearFinish = try matcher.match(latitude: 0.00002, longitude: 0.00002, horizontalAccuracy: 5)
        XCTAssertLessThan(first.progress, second.progress)
        XCTAssertGreaterThan(nearFinish.progress, 0.9)
    }

    func testOutAndBackAmbiguityAdvancesOntoReturnLeg() throws {
        let route = try Route(name: "Out and Back", originalFilename: "out-back.gpx", segments: [
            .init(points: [point(0, 0), point(0, 0.001), point(0, 0.002), point(0, 0.001), point(0, 0)])
        ])
        var matcher = RouteMatcher(route: route)
        _ = try matcher.match(latitude: 0, longitude: 0.0005, horizontalAccuracy: 5)
        _ = try matcher.match(latitude: 0, longitude: 0.0015, horizontalAccuracy: 5)
        _ = try matcher.match(latitude: 0, longitude: 0.00195, horizontalAccuracy: 5)
        let returning = try matcher.match(latitude: 0, longitude: 0.00175, horizontalAccuracy: 5)
        XCTAssertEqual(returning.edgeIndex, 2)
        XCTAssertGreaterThan(returning.progress, 0.5)
    }

    func testMatcherChoosesCorrectDisconnectedSegment() throws {
        let route = try Route(name: "Split", originalFilename: "split.gpx", segments: [
            .init(points: [point(0, 0), point(0, 0.001)]),
            .init(points: [point(1, 1), point(1, 1.001)])
        ])
        var matcher = RouteMatcher(route: route)
        let match = try matcher.match(latitude: 1.0001, longitude: 1.0005, horizontalAccuracy: 5)
        XCTAssertEqual(match.segmentIndex, 1)
        XCTAssertEqual(match.distanceFromRoute, 11.1, accuracy: 1)
    }

    func testProjectionAcrossAntimeridian() throws {
        let route = try Route(name: "Dateline", originalFilename: "dateline.gpx", segments: [
            .init(points: [point(0, 179.999), point(0, -179.999)])
        ])
        var matcher = RouteMatcher(route: route)
        let match = try matcher.match(latitude: 0.0001, longitude: 180, horizontalAccuracy: 5)
        XCTAssertEqual(match.distanceFromRoute, 11.1, accuracy: 1)
        XCTAssertEqual(match.progress, 0.5, accuracy: 0.02)
    }

    func testSimplifierPreservesSegmentBoundariesAndShape() throws {
        let route = try Route(name: "Shape", originalFilename: "shape.gpx", segments: [
            .init(points: [point(0, 0), point(0, 0.0001), point(0, 0.0002)]),
            .init(points: [point(1, 1), point(1.001, 1.001), point(1.002, 1)])
        ], targetPaceSecondsPerKilometer: 330)
        let simplified = try RouteSimplifier.simplify(route, tolerance: 3)
        XCTAssertEqual(simplified.id, route.id)
        XCTAssertEqual(simplified.segments.count, 2)
        XCTAssertEqual(simplified.segments[0].points.count, 2)
        XCTAssertEqual(simplified.segments[1].points.count, 3)
        XCTAssertEqual(simplified.targetPaceSecondsPerKilometer, 330)
    }

    func testWatchSimplifierRejectsGeometryThatCannotBeReducedSafely() throws {
        let route = try Route(name: "Zigzag", originalFilename: "zigzag.gpx", segments: [
            .init(points: [point(0, 0), point(0.001, 0.001), point(0, 0.002)])
        ])
        XCTAssertThrowsError(try RouteSimplifier.simplifyForWatch(route, maximumPointCount: 2, maximumTolerance: 3)) {
            XCTAssertEqual($0 as? RouteSimplificationError, .tooDetailedForWatch)
        }
    }

    func testPoorLocationAccuracyIsIgnored() throws {
        let route = try Route(name: "Line", originalFilename: "line", segments: [.init(points: [point(0, 0), point(0, 1)])])
        var matcher = RouteMatcher(route: route)
        XCTAssertThrowsError(try matcher.match(latitude: 0, longitude: 0, horizontalAccuracy: 100)) { XCTAssertEqual($0 as? RouteMatchingError, .poorHorizontalAccuracy) }
    }

    func testAlertHysteresisAndCooldown() {
        var alert = OffCourseAlertState()
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(alert.update(distance: 41, at: start), .wentOffCourse)
        XCTAssertEqual(alert.update(distance: 30, at: start.addingTimeInterval(10)), .none)
        XCTAssertEqual(alert.update(distance: 41, at: start.addingTimeInterval(21)), .repeatWarning)
        XCTAssertEqual(alert.update(distance: 24, at: start.addingTimeInterval(22)), .returnedToRoute)
    }

    func testPaceProgressUsesCourseDistance() throws {
        let progress = try XCTUnwrap(PaceCalculator.progress(
            targetPaceSecondsPerKilometer: 300,
            elapsed: 1_650,
            distanceCompleted: 5_000,
            plannedDistance: 10_000
        ))
        XCTAssertEqual(progress.averagePaceSecondsPerKilometer, 330, accuracy: 0.001)
        XCTAssertEqual(progress.plannedElapsed, 1_500, accuracy: 0.001)
        XCTAssertEqual(progress.scheduleDelta, 150, accuracy: 0.001)
        XCTAssertEqual(progress.projectedDuration, 3_300, accuracy: 0.001)
    }

    func testPaceAlertWaitsForReliableWarmup() {
        var alert = PaceAlertState()
        XCTAssertEqual(alert.update(averagePace: 400, targetPace: 300, distanceCompleted: 499, elapsed: 400), .none)
        XCTAssertEqual(alert.update(averagePace: 400, targetPace: 300, distanceCompleted: 600, elapsed: 179), .none)
        XCTAssertFalse(alert.isBehind)
    }

    func testPaceAlertHysteresisAndCooldown() {
        var alert = PaceAlertState()
        XCTAssertEqual(alert.update(averagePace: 331, targetPace: 300, distanceCompleted: 600, elapsed: 200), .fellBehind)
        XCTAssertEqual(alert.update(averagePace: 318, targetPace: 300, distanceCompleted: 700, elapsed: 250), .none)
        XCTAssertEqual(alert.update(averagePace: 318, targetPace: 300, distanceCompleted: 900, elapsed: 320), .repeatWarning)
        XCTAssertEqual(alert.update(averagePace: 315, targetPace: 300, distanceCompleted: 1_000, elapsed: 330), .caughtUp)
        XCTAssertFalse(alert.isBehind)
    }
}
