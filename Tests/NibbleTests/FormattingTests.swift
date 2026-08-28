import XCTest
@testable import NibbleCore

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

    func testCodexBarText() {
        let windows = [
            LimitWindow(kind: "weekly", percent: 40),
            LimitWindow(kind: "session", percent: 12),
        ]
        XCTAssertEqual(Formatting.barText(windows), "5h 12% · wk 40%")
    }

    func testCodexBarTextWithCredits() {
        let windows = [
            LimitWindow(kind: "session", percent: 12),
            LimitWindow(kind: "weekly", percent: 40),
            LimitWindow(kind: "credits", percent: 10),
        ]
        XCTAssertEqual(Formatting.barText(windows), "5h 12% · wk 40% · cr 10%")
    }

    func testGrokWeeklyBarText() {
        XCTAssertEqual(
            Formatting.barText([LimitWindow(kind: "weekly", percent: 61)]),
            "wk 61%")
    }

    func testGrokMonthlyBarText() {
        XCTAssertEqual(
            Formatting.barText([LimitWindow(kind: "monthly", percent: 61)]),
            "mo 61%")
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
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(23 * 3600 + 59 * 60), now: now), "resets in 23h 59m")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(14 * 60), now: now), "resets in 14m")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(30), now: now), "resets in <1m")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(-5), now: now), "resetting…")
    }

    /// Weekly windows run to ~168h, which reads as noise in hours.
    func testCountdownSwitchesToDaysPastOneDay() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(113 * 3600 + 48 * 60), now: now), "resets in 4d 17h")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(24 * 3600), now: now), "resets in 1d")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(24 * 3600 + 30 * 60), now: now), "resets in 1d")
        XCTAssertEqual(Formatting.countdown(until: now.addingTimeInterval(6 * 24 * 3600 + 23 * 3600), now: now), "resets in 6d 23h")
    }
}
