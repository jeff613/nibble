import XCTest
@testable import UsageBarCore

final class UsageDecodingTests: XCTestCase {
    static let fixture = Data("""
    {
      "five_hour": {"utilization": 88.0, "resets_at": "2026-08-02T09:20:00.953490+00:00"},
      "seven_day_opus": null,
      "limits": [
        {"kind": "session", "group": "session", "percent": 88, "severity": "warning",
         "resets_at": "2026-08-02T09:20:00.347559+00:00", "scope": null, "is_active": true},
        {"kind": "weekly_all", "group": "weekly", "percent": 75, "severity": "warning",
         "resets_at": "2026-08-02T11:00:00.347578+00:00", "scope": null, "is_active": false},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 81, "severity": "warning",
         "resets_at": "2026-08-02T11:00:00.347793+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false},
        {"kind": "future_unknown_thing", "percent": "not-a-number"}
      ]
    }
    """.utf8)

    func testParsesLimitsArray() throws {
        let windows = try UsageResponseParser.parse(Self.fixture)
        XCTAssertEqual(windows.count, 3)  // malformed 4th entry skipped
        XCTAssertEqual(windows[0].kind, "session")
        XCTAssertEqual(windows[0].percent, 88)
        XCTAssertEqual(windows[2].modelName, "Fable")
        XCTAssertNil(windows[1].modelName)
        XCTAssertNotNil(windows[0].resetsAt)
    }

    func testParsesFractionalSecondsDate() {
        let d = DateParsing.parse("2026-08-02T09:20:00.953490+00:00")
        XCTAssertNotNil(d)
        let z = DateParsing.parse("2026-08-01T22:15:03.123Z")
        XCTAssertNotNil(z)
    }

    func testMissingLimitsThrows() {
        XCTAssertThrowsError(try UsageResponseParser.parse(Data("{}".utf8)))
    }
}
