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

    func testLoopOutAndBackAndStartNearFinishRemainMatchable() throws {
        let loop = try Route(name: "Loop", originalFilename: "loop.gpx", segments: [.init(points: [point(0, 0), point(0, 0.001), point(0.001, 0.001), point(0.00001, 0.00001)])])
        var matcher = RouteMatcher(route: loop)
        XCTAssertNoThrow(try matcher.match(latitude: 0, longitude: 0.0005, horizontalAccuracy: 5))
        XCTAssertNoThrow(try matcher.match(latitude: 0.0005, longitude: 0.001, horizontalAccuracy: 5))
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
}
