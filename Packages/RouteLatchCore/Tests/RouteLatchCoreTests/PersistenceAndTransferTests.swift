import Foundation
import XCTest
@testable import RouteLatchCore

final class PersistenceAndTransferTests: XCTestCase {
    private func route(id: UUID = UUID(), fingerprint: String? = "fingerprint") throws -> Route {
        try Route(id: id, name: "Test", originalFilename: "test.gpx", segments: [.init(points: [try .init(latitude: 47, longitude: 19), try .init(latitude: 47.01, longitude: 19.01)])], sourceFingerprint: fingerprint, targetPaceSecondsPerKilometer: 345)
    }

    func testCodecRoundTrip() throws {
        let original = try route()
        XCTAssertEqual(try RouteTransferCodec.decode(RouteTransferCodec.encode(original)), original)
    }

    func testCodecDecodesRoutesCreatedBeforePaceGoals() throws {
        let data = try RouteTransferCodec.encode(route())
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var routeJSON = try XCTUnwrap(envelope["route"] as? [String: Any])
        routeJSON.removeValue(forKey: "targetPaceSecondsPerKilometer")
        envelope["route"] = routeJSON
        let decoded = try RouteTransferCodec.decode(JSONSerialization.data(withJSONObject: envelope))
        XCTAssertNil(decoded.targetPaceSecondsPerKilometer)
    }

    func testPaceGoalValidation() throws {
        XCTAssertThrowsError(try Route(
            name: "Too Fast",
            originalFilename: "fast.gpx",
            segments: [.init(points: [try .init(latitude: 47, longitude: 19), try .init(latitude: 47.01, longitude: 19.01)])],
            targetPaceSecondsPerKilometer: 120
        ))
    }

    func testPersistenceRoundTripAndDuplicateDetection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RouteFileStore(directory: directory), original = try route()
        try store.save(original)
        XCTAssertEqual(store.loadAll().routes, [original])
        XCTAssertThrowsError(try store.save(route())) { XCTAssertEqual($0 as? RouteStoreError, .duplicateRoute) }
    }

    func testRepeatedReceiptOfSameRouteIsIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RouteFileStore(directory: directory)
        let transferred = try route()
        try store.save(try RouteTransferCodec.decode(RouteTransferCodec.encode(transferred)))
        try store.save(try RouteTransferCodec.decode(RouteTransferCodec.encode(transferred)))
        XCTAssertEqual(store.loadAll().routes, [transferred])
    }

    func testCorruptRouteIsIsolated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RouteFileStore(directory: directory), original = try route()
        try store.save(original)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("damaged.route"))
        let result = store.loadAll()
        XCTAssertEqual(result.routes.count, 1)
        XCTAssertEqual(result.routes.first?.id, original.id)
        XCTAssertEqual(result.routes.first?.segments, original.segments)
        XCTAssertEqual(result.issues.count, 1)
    }

    func testFutureSchemaRejected() throws {
        let data = try RouteTransferCodec.encode(route())
        let text = try XCTUnwrap(String(data: data, encoding: .utf8)).replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
        XCTAssertThrowsError(try RouteTransferCodec.decode(Data(text.utf8)))
    }

    func testFutureEmbeddedRouteSchemaReportsItsVersion() throws {
        let future = try Route(
            name: "Future",
            originalFilename: "future.gpx",
            segments: [.init(points: [try .init(latitude: 47, longitude: 19), try .init(latitude: 47.1, longitude: 19.1)])],
            schemaVersion: 42
        )
        XCTAssertThrowsError(try RouteTransferCodec.decode(RouteTransferCodec.encode(future))) {
            XCTAssertEqual($0 as? RouteValidationError, .unsupportedSchema(42))
        }
    }
}
