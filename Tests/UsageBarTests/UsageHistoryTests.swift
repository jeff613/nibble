import XCTest
@testable import UsageBarCore

final class UsageHistoryTests: XCTestCase {
    let assistantLine = #"{"type":"assistant","timestamp":"2026-08-01T10:00:00.000Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-fable-5","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000}}}"#

    func testParsesAssistantLine() throws {
        let e = try XCTUnwrap(UsageLineParser.parse(assistantLine))
        XCTAssertEqual(e.model, "claude-fable-5")
        XCTAssertEqual(e.input, 10)
        XCTAssertEqual(e.output, 20)
        XCTAssertEqual(e.cacheCreation, 100)
        XCTAssertEqual(e.cacheRead, 1000)
        XCTAssertEqual(e.dedupeKey, "msg_1:req_1")
    }

    func testIgnoresNonAssistantAndGarbage() {
        XCTAssertNil(UsageLineParser.parse(#"{"type":"user","message":{"content":"hi"}}"#))
        XCTAssertNil(UsageLineParser.parse("not json"))
        XCTAssertNil(UsageLineParser.parse(#"{"type":"assistant","timestamp":"2026-08-01T10:00:00Z","message":{"model":"m"}}"#))
    }

    func testFoldAggregatesAndDedupes() throws {
        let utc = TimeZone(identifier: "UTC")!
        let e = try XCTUnwrap(UsageLineParser.parse(assistantLine))
        var totals: [DayModelKey: TokenCounts] = [:]
        var seen = Set<String>()
        UsageAggregator.fold(events: [e, e], into: &totals, seen: &seen, timeZone: utc)
        let key = DayModelKey(day: "2026-08-01", model: "claude-fable-5")
        XCTAssertEqual(totals[key]?.output, 20)
        XCTAssertEqual(totals[key]?.total, 10 + 20 + 100 + 1000)
        XCTAssertEqual(totals.count, 1)
    }

    func testDayKeyUsesTimeZone() {
        let date = DateParsing.parse("2026-08-01T23:30:00Z")!
        XCTAssertEqual(UsageAggregator.dayKey(for: date, timeZone: TimeZone(identifier: "UTC")!), "2026-08-01")
        XCTAssertEqual(UsageAggregator.dayKey(for: date, timeZone: TimeZone(identifier: "Asia/Tokyo")!), "2026-08-02")
    }
}
