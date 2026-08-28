import XCTest
@testable import NibbleCore

final class GrokUsageTests: XCTestCase {
    func testParsesWeeklyCreditsPercent() {
        let data = Data(#"""
        {
          "config": {
            "creditUsagePercent": 42.5,
            "currentPeriod": {
              "type": "USAGE_PERIOD_TYPE_WEEKLY",
              "start": "2026-06-01T00:00:00Z",
              "end": "2026-06-08T00:00:00Z"
            }
          }
        }
        """#.utf8)
        let windows = GrokUsageParser.parse(data)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].kind, "weekly")
        XCTAssertEqual(windows[0].percent, 42.5)
        XCTAssertEqual(windows[0].resetsAt, DateParsing.parse("2026-06-08T00:00:00Z"))
    }

    func testParsesMonthlyFromRootConfig() {
        let data = Data(#"""
        {
          "creditUsagePercent": 10,
          "currentPeriod": {"type": "USAGE_PERIOD_TYPE_MONTHLY", "end": "2026-07-01T00:00:00Z"}
        }
        """#.utf8)
        let windows = GrokUsageParser.parse(data)
        XCTAssertEqual(windows.map(\.kind), ["monthly"])
        XCTAssertEqual(windows.first?.percent, 10)
    }

    func testMissingPercentYieldsNoWindows() {
        let data = Data(#"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"}}}"#.utf8)
        XCTAssertEqual(GrokUsageParser.parse(data), [])
    }
}
