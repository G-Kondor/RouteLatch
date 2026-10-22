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
        let encoded = AppearanceSync.payload(preference: .dark, resolved: .dark)
        var context: [String: Any] = [:]
        for (key, value) in encoded { context[key] = value }
        let snapshot = AppearanceSnapshot(preference: .dark, resolved: .dark)
        XCTAssertEqual(AppearanceSync.snapshot(from: context), snapshot)
    }

    func testAppearanceRequestIsNotAThemeSnapshot() {
        let message: [String: Any] = [AppearanceSync.requestKey: "1"]
        XCTAssertTrue(AppearanceSync.isRequest(message))
        XCTAssertNil(AppearanceSync.snapshot(from: message))
        var theme: [String: Any] = [:]
        for (key, value) in AppearanceSync.payload(preference: .dark, resolved: .dark) { theme[key] = value }
        XCTAssertFalse(AppearanceSync.isRequest(theme))
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
