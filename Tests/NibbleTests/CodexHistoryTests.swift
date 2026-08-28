import XCTest
@testable import NibbleCore

final class CodexHistoryTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!
    let context = #"{"timestamp":"2026-08-28T10:00:00Z","ordinal":1,"type":"turn_context","payload":{"model":"gpt-5.6-sol"}}"#
    let tokens = #"{"timestamp":"2026-08-28T10:00:01Z","ordinal":2,"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":4,"cache_write_input_tokens":2,"output_tokens":20}}}}"#

    func testFoldsLastTokenUsageWithTurnModel() {
        var model = "unknown"
        var totals: [DayModelKey: TokenCounts] = [:]
        var seen = Set<String>()
        XCTAssertEqual(CodexLineParser.consume(context, model: &model, into: &totals, seen: &seen, timeZone: utc), 0)
        XCTAssertEqual(model, "gpt-5.6-sol")
        XCTAssertEqual(CodexLineParser.consume(tokens, model: &model, into: &totals, seen: &seen, timeZone: utc), 1)
        let key = DayModelKey(day: "2026-08-28", model: "gpt-5.6-sol")
        XCTAssertEqual(totals[key]?.input, 10)
        XCTAssertEqual(totals[key]?.output, 20)
        XCTAssertEqual(totals[key]?.cacheRead, 4)
        XCTAssertEqual(totals[key]?.cacheCreation, 2)
    }

    func testDedupesRepeatedTokenCount() {
        var model = "unknown"
        var totals: [DayModelKey: TokenCounts] = [:]
        var seen = Set<String>()
        _ = CodexLineParser.consume(context, model: &model, into: &totals, seen: &seen, timeZone: utc)
        XCTAssertEqual(CodexLineParser.consume(tokens, model: &model, into: &totals, seen: &seen, timeZone: utc), 1)
        XCTAssertEqual(CodexLineParser.consume(tokens, model: &model, into: &totals, seen: &seen, timeZone: utc), 0)
        XCTAssertEqual(totals.values.first?.output, 20)
    }

    func testUnknownModelWhenNoTurnContext() {
        var model = "unknown"
        var totals: [DayModelKey: TokenCounts] = [:]
        var seen = Set<String>()
        _ = CodexLineParser.consume(tokens, model: &model, into: &totals, seen: &seen, timeZone: utc)
        XCTAssertNotNil(totals[DayModelKey(day: "2026-08-28", model: "unknown")])
    }

    func testScannerReadsRolloutFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = dir.appendingPathComponent("sessions/2026/08/28")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let body = [context, tokens].joined(separator: "\n")
        try body.write(to: nested.appendingPathComponent("rollout-2026-08-28T10-00-00.jsonl"), atomically: true, encoding: .utf8)
        let scanner = CodexHistoryScanner(root: dir, timeZone: utc)
        let now = DateParsing.parse("2026-08-28T12:00:00Z")!
        let totals = scanner.scan(now: now)
        XCTAssertEqual(scanner.newEventsInLastScan, 1)
        XCTAssertEqual(totals[DayModelKey(day: "2026-08-28", model: "gpt-5.6-sol")]?.output, 20)
        try? FileManager.default.removeItem(at: dir)
    }
}
