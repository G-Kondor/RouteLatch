import Foundation
import XCTest
@testable import RouteLatchCore

final class GPXParserTests: XCTestCase {
    func testValidTrackPreservesSegmentsElevationAndTime() throws {
        let route = try GPXParser().parse(url: try XCTUnwrap(Bundle.module.url(forResource: "track", withExtension: "gpx")))
        XCTAssertEqual(route.name, "Hill Loop")
        XCTAssertEqual(route.segments.count, 2)
        XCTAssertEqual(route.pointCount, 3)
        XCTAssertEqual(route.totalAscent, 12)
        XCTAssertEqual(route.totalDescent, 0)
        XCTAssertNotNil(route.start.timestamp)
    }

    func testRouteOnlyFile() throws {
        let route = try GPXParser().parse(url: try XCTUnwrap(Bundle.module.url(forResource: "route", withExtension: "gpx")))
        XCTAssertEqual(route.name, "River Run")
        XCTAssertEqual(route.segments.count, 1)
    }

    func testNamespacedGPX() throws {
        let route = try GPXParser().parse(url: try XCTUnwrap(Bundle.module.url(forResource: "namespaced", withExtension: "gpx")))
        XCTAssertEqual(route.name, "Namespaced")
        XCTAssertEqual(route.pointCount, 2)
    }

    func testMalformedXML() {
        XCTAssertThrowsError(try GPXParser().parse(data: Data("<gpx><trk>".utf8)))
    }

    func testInvalidCoordinate() {
        XCTAssertThrowsError(try GPXParser().parse(data: Data("<gpx><rte><rtept lat=\"900\" lon=\"19\"/></rte></gpx>".utf8))) { XCTAssertEqual($0 as? GPXError, .invalidCoordinate) }
    }

    func testMissingCoordinate() {
        XCTAssertThrowsError(try GPXParser().parse(data: Data("<gpx><rte><rtept lat=\"47\"/></rte></gpx>".utf8))) { XCTAssertEqual($0 as? GPXError, .missingCoordinate) }
    }

    func testEmptyRoute() {
        XCTAssertThrowsError(try GPXParser().parse(data: Data("<gpx><trk><trkseg/></trk></gpx>".utf8))) { XCTAssertEqual($0 as? GPXError, .emptyRoute) }
    }

    func testSinglePointRouteIsRejectedAsUnusable() {
        let data = Data("<gpx><rte><rtept lat=\"47\" lon=\"19\"/></rte></gpx>".utf8)
        XCTAssertThrowsError(try GPXParser().parse(data: data)) { XCTAssertEqual($0 as? GPXError, .emptyRoute) }
    }

    func testCDATANameAndFractionalTimestamp() throws {
        let xml = """
        <gpx><trk><name><![CDATA[Forest & Ridge]]></name><trkseg>
        <trkpt lat="47" lon="19"><time>2026-08-27T10:15:30.125Z</time></trkpt>
        <trkpt lat="47.001" lon="19.001"/>
        </trkseg></trk></gpx>
        """
        let route = try GPXParser().parse(data: Data(xml.utf8))
        XCTAssertEqual(route.name, "Forest & Ridge")
        XCTAssertNotNil(route.start.timestamp)
    }

    func testOversizedInput() {
        let data = Data("<gpx><rte><rtept lat=\"47\" lon=\"19\"/><rtept lat=\"47.1\" lon=\"19.1\"/></rte></gpx>".utf8)
        XCTAssertThrowsError(try GPXParser(maximumPointCount: 1).parse(data: data)) { XCTAssertEqual($0 as? GPXError, .tooManyPoints(1)) }
    }

    func testBundledSpartacusDefaultRoute() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = testDirectory.appendingPathComponent("../../../../Resources/DefaultRoute.gpx").standardizedFileURL
        let route = try GPXParser().parse(url: url)
        XCTAssertEqual(route.pointCount, 1_332)
        XCTAssertEqual(route.segments.count, 1)
        XCTAssertGreaterThan(route.totalDistance, 1_000)
        XCTAssertNotNil(route.sourceFingerprint)
    }
}
