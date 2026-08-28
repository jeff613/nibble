import XCTest
@testable import NibbleCore

final class CodexUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    let bothWindows = Data(#"""
    {
      "rate_limit": {
        "primary_window": {"used_percent": 12, "window_minutes": 300, "reset_after_seconds": 7200},
        "secondary_window": {"used_percent": 40, "window_minutes": 10080, "reset_after_seconds": 432000}
      },
      "credits": {"has_credits": false, "unlimited": false, "balance": "0"}
    }
    """#.utf8)

    func testParsesSessionAndWeeklyByDuration() {
        let windows = CodexUsageParser.parse(bothWindows, now: now)
        XCTAssertEqual(windows.map(\.kind), ["session", "weekly"])
        XCTAssertEqual(windows.map(\.percent), [12, 40])
        XCTAssertEqual(windows[0].resetsAt, now.addingTimeInterval(7200))
        XCTAssertEqual(windows[1].resetsAt, now.addingTimeInterval(432000))
    }

    func testOmitsCreditsWhenHasCreditsIsFalse() {
        let windows = CodexUsageParser.parse(bothWindows, now: now)
        XCTAssertFalse(windows.contains { $0.kind == "credits" })
    }

    func testWeeklyOnlyPayload() {
        let data = Data(#"""
        {
          "rate_limit": {
            "secondary_window": {"used_percent": 40, "window_minutes": 10080, "reset_at": 1000000}
          }
        }
        """#.utf8)
        let windows = CodexUsageParser.parse(data, now: now)
        XCTAssertEqual(windows.map(\.kind), ["weekly"])
        XCTAssertEqual(windows.first?.resetsAt, Date(timeIntervalSince1970: 1_000_000))
    }

    func testCreditsRowWhenPresent() {
        let data = Data(#"""
        {
          "rate_limit": {
            "primary_window": {"used_percent": 12, "window_minutes": 300}
          },
          "credits": {"has_credits": true, "unlimited": false, "used_percent": 10}
        }
        """#.utf8)
        let windows = CodexUsageParser.parse(data, now: now)
        XCTAssertEqual(windows.map(\.kind), ["session", "credits"])
        XCTAssertEqual(windows.last?.percent, 10)
    }

    func testIgnoresMalformedJSON() {
        XCTAssertEqual(CodexUsageParser.parse(Data("nope".utf8)), [])
    }
}
