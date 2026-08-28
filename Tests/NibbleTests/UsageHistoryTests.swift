import XCTest
@testable import NibbleCore

final class UsageHistoryTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!
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

    func testDayFamilyTotalsStackInCanonicalOrderEveryDay() {
        var counts = TokenCounts()
        counts.input = 1
        // Insertion order deliberately jumbled: the totals dictionary has no
        // order, so the output must impose one.
        let totals: [DayModelKey: TokenCounts] = [
            DayModelKey(day: "2026-08-05", model: "claude-sonnet-5"): counts,
            DayModelKey(day: "2026-08-04", model: "claude-opus-5"): counts,
            DayModelKey(day: "2026-08-05", model: "claude-fable-5"): counts,
            DayModelKey(day: "2026-08-04", model: "claude-fable-5"): counts,
            DayModelKey(day: "2026-08-05", model: "claude-opus-5"): counts,
        ]
        let segments = UsageAggregator.dayFamilyTotals(totals)
        XCTAssertEqual(segments.map(\.day),
                       ["2026-08-04", "2026-08-04", "2026-08-05", "2026-08-05", "2026-08-05"])
        XCTAssertEqual(segments.map(\.family),
                       ["fable-5", "opus-5", "fable-5", "opus-5", "sonnet-5"])
    }

    func testDayFamilyTotalsKeepsEmptyCalendarDays() {
        var counts = TokenCounts()
        counts.input = 1
        let totals: [DayModelKey: TokenCounts] = [
            DayModelKey(day: "2026-08-20", model: "claude-fable-5"): counts,
            DayModelKey(day: "2026-08-26", model: "claude-opus-5"): counts,
        ]
        let days = ["2026-08-20", "2026-08-21", "2026-08-22", "2026-08-23",
                    "2026-08-24", "2026-08-25", "2026-08-26"]
        let segments = UsageAggregator.dayFamilyTotals(totals, days: days)
        XCTAssertEqual(Set(segments.map(\.day)).sorted(), days)
        XCTAssertEqual(segments.first { $0.day == "2026-08-24" }?.tokens, 0)
        XCTAssertEqual(segments.first { $0.day == "2026-08-20" }?.tokens, 1)
        XCTAssertEqual(segments.first { $0.day == "2026-08-20" }?.family, "fable-5")
        XCTAssertEqual(segments.first { $0.day == "2026-08-26" }?.family, "opus-5")
    }

    func testDayFamilyTotalsEmptyHistoryStaysEmpty() {
        let days = ["2026-08-20", "2026-08-21"]
        XCTAssertEqual(UsageAggregator.dayFamilyTotals([:], days: days), [])
    }

    func testDayFamilyTotalsKeepsVersionedModelsApart() {
        var ten = TokenCounts()
        ten.input = 10
        var one = TokenCounts()
        one.input = 1
        let totals: [DayModelKey: TokenCounts] = [
            DayModelKey(day: "2026-08-04", model: "claude-opus-5"): ten,
            DayModelKey(day: "2026-08-04", model: "claude-opus-4-8"): one,
        ]
        let segments = UsageAggregator.dayFamilyTotals(totals)
        XCTAssertEqual(segments.map(\.family), ["opus-4-8", "opus-5"])
        XCTAssertEqual(segments.map(\.tokens), [1, 10])
    }

    func testDayKeyUsesTimeZone() {
        let date = DateParsing.parse("2026-08-01T23:30:00Z")!
        XCTAssertEqual(UsageAggregator.dayKey(for: date, timeZone: TimeZone(identifier: "UTC")!), "2026-08-01")
        XCTAssertEqual(UsageAggregator.dayKey(for: date, timeZone: TimeZone(identifier: "Asia/Tokyo")!), "2026-08-02")
    }

    func testHistoryMergeUnionsOverlappingDays() {
        var a = TokenCounts(); a.input = 1
        var b = TokenCounts(); b.output = 2
        let left = [DayModelKey(day: "2026-08-01", model: "opus-5"): a]
        let right = [
            DayModelKey(day: "2026-08-01", model: "opus-5"): b,
            DayModelKey(day: "2026-08-01", model: "grok-4.6"): b,
        ]
        let merged = HistoryMerge.union([left, right])
        XCTAssertEqual(merged[DayModelKey(day: "2026-08-01", model: "opus-5")]?.total, 3)
        XCTAssertEqual(merged[DayModelKey(day: "2026-08-01", model: "grok-4.6")]?.output, 2)
    }

    func testLastSevenDaysAreCalendarDaysIncludingToday() {
        let now = DateParsing.parse("2026-08-26T15:00:00Z")!
        XCTAssertEqual(
            UsageAggregator.lastSevenDays(endingOn: now, timeZone: utc),
            ["2026-08-20", "2026-08-21", "2026-08-22", "2026-08-23",
             "2026-08-24", "2026-08-25", "2026-08-26"])
    }

    /// 6 × 86400 seconds back from 00:30 after a spring-forward lands on the
    /// previous calendar day; the window must still be seven local dates.
    func testLastSevenDaysUsesCalendarDatesAcrossDST() {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 0, minute: 30))!
        XCTAssertEqual(
            UsageAggregator.lastSevenDays(endingOn: now, timeZone: tz),
            ["2026-03-08", "2026-03-09", "2026-03-10", "2026-03-11",
             "2026-03-12", "2026-03-13", "2026-03-14"])
    }
}
