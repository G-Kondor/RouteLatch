import XCTest
@testable import RouteLatchCore

final class AppearanceSyncTests: XCTestCase {
    func testSystemFollowsThePhoneSchemeWhileExplicitChoicesStayFixed() {
        XCTAssertEqual(ResolvedAppearance.matching(preference: .system, phoneScheme: .dark), .dark)
        XCTAssertEqual(ResolvedAppearance.matching(preference: .system, phoneScheme: .light), .light)
        XCTAssertEqual(ResolvedAppearance.matching(preference: .light, phoneScheme: .dark), .light)
        XCTAssertEqual(ResolvedAppearance.matching(preference: .dark, phoneScheme: .light), .dark)
    }

    func testAppearancePayloadRoundTripsThroughWatchContext() {
        let payload = AppearanceSync.payload(preference: .dark, resolved: .dark)
        let snapshot = AppearanceSnapshot(preference: .dark, resolved: .dark)
        XCTAssertEqual(AppearanceSync.snapshot(from: payload), snapshot)
    }

    func testAppearancePayloadIgnoresIncompleteOrUnknownValues() {
        XCTAssertNil(AppearanceSync.snapshot(from: [:]))
        XCTAssertNil(AppearanceSync.snapshot(from: [AppAppearance.preferenceContextKey: "light"]))
        XCTAssertNil(AppearanceSync.snapshot(from: [
            AppAppearance.preferenceContextKey: "sepia",
            AppAppearance.resolvedContextKey: "dark"
        ]))
        XCTAssertEqual(AppAppearance.stored("nope"), .system)
    }
}
