import Foundation
import XCTest
@testable import RouteLatchCore

final class RecordedRunTests: XCTestCase {
    private func recordedRun() -> RecordedRun {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return RecordedRun(
            name: "Morning & Trail Run",
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            activeDuration: 570,
            distanceMeters: 2_000,
            points: [
                .init(latitude: 47.5, longitude: 19.0, elevation: 110, timestamp: start, heartRate: 120),
                .init(latitude: 47.51, longitude: 19.01, elevation: 115, timestamp: start.addingTimeInterval(600), heartRate: 145)
            ]
        )
    }

    func testRecordedRunCodecRoundTrip() throws {
        let original = recordedRun()
        XCTAssertEqual(try RecordedRunCodec.decode(RecordedRunCodec.encode(original)), original)
    }

    func testTCXContainsActualMetricsAndEscapedName() throws {
        let text = try XCTUnwrap(String(data: TCXEncoder.encode(recordedRun()), encoding: .utf8))
        XCTAssertTrue(text.contains("<TotalTimeSeconds>570.0</TotalTimeSeconds>"))
        XCTAssertEqual(text.components(separatedBy: "<DistanceMeters>2000.0</DistanceMeters>").count - 1, 2)
        XCTAssertTrue(text.contains("Morning &amp; Trail Run"))
        XCTAssertTrue(text.contains("<LatitudeDegrees>47.5</LatitudeDegrees>"))
        XCTAssertTrue(text.contains("<Value>120</Value>"))
        XCTAssertTrue(text.contains("<DistanceMeters>2000.0</DistanceMeters>"))
    }

    func testStoreCreatesTransferAndTCXFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordedRunFileStore(directory: directory)
        let original = recordedRun()
        try store.save(original)
        XCTAssertEqual(store.loadAll().runs, [original])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.tcxURL(for: original.id).path))
        try store.delete(original)
        XCTAssertTrue(store.loadAll().runs.isEmpty)
    }
}
