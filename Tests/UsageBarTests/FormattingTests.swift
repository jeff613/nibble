import XCTest
@testable import UsageBarCore

final class FormattingTests: XCTestCase {
    let windows = [
        LimitWindow(kind: "weekly_scoped", percent: 81, modelName: "Fable"),
        LimitWindow(kind: "session", percent: 88),
        LimitWindow(kind: "weekly_all", percent: 75),
    ]

    func testBarTextOrderAndLabels() {
        XCTAssertEqual(Formatting.barText(windows), "5h 88% · wk 75% · F 81%")
    }

    func testBarTextEmpty() {
        XCTAssertEqual(Formatting.barText([]), "—")
    }

    func testUnknownKindUsesKindPrefix() {
        let w = [LimitWindow(kind: "monthly_all", percent: 10)]
        XCTAssertEqual(Formatting.barText(w), "mo 10%")
    }

    func testSeverityThresholds() {
        XCTAssertEqual(Formatting.severity([LimitWindow(kind: "session", percent: 50)]), .normal)
        XCTAssertEqual(Formatting.severity([LimitWindow(kind: "session", percent: 75)]), .warning)
        XCTAssertEqual(Formatting.severity(windows), .warning)
        XCTAssertEqual(Formatting.severity([LimitWindow(kind: "session", percent: 92)]), .critical)
        XCTAssertEqual(Formatting.severity([]), .normal)
    }

    func testCompactCount() {
        XCTAssertEqual(Formatting.compactCount(0), "0")
        XCTAssertEqual(Formatting.compactCount(999), "999")
        XCTAssertEqual(Formatting.compactCount(1_000), "1K")
        XCTAssertEqual(Formatting.compactCount(45_300), "45.3K")
        XCTAssertEqual(Formatting.compactCount(1_200_000), "1.2M")
        XCTAssertEqual(Formatting.compactCount(300_000_000), "300M")
        XCTAssertEqual(Formatting.compactCount(2_500_000_000), "2.5B")
    }

    func testDuration() {
        XCTAssertEqual(Formatting.duration(0), "0s")
        XCTAssertEqual(Formatting.duration(-5), "0s")
        XCTAssertEqual(Formatting.duration(45), "45s")
        XCTAssertEqual(Formatting.duration(60), "1m")
        XCTAssertEqual(Formatting.duration(1985), "33m")
        XCTAssertEqual(Formatting.duration(3600), "1h")
        XCTAssertEqual(Formatting.duration(3900), "1h 5m")
    }

    func testCountdown() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(2 * 3600 + 14 * 60), now: now), "resets in 2h 14m")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(14 * 60), now: now), "resets in 14m")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(30), now: now), "resets in <1m")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(-5), now: now), "resetting…")
    }
}
