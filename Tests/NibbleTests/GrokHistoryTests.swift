import XCTest
@testable import NibbleCore

final class GrokHistoryTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!
    let turn = #"{"timestamp":1787800690,"method":"session/update","params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"p1","usage":{"modelUsage":{"grok-4.6-build":{"inputTokens":10,"outputTokens":20,"cachedReadTokens":4,"cacheCreationTokens":2}}}},"_meta":{"agentTimestampMs":1787800690000}}}"#

    func testFoldsTurnCompletedModelUsage() {
        var totals: [DayModelKey: TokenCounts] = [:]
        var seen = Set<String>()
        XCTAssertEqual(GrokLineParser.consume(turn, into: &totals, seen: &seen, timeZone: utc), 1)
        let key = DayModelKey(day: "2026-08-27", model: "grok-4.6-build")
        // 1787800690 = 2026-08-27 03:18:10 UTC
        XCTAssertEqual(totals[key]?.input, 10)
        XCTAssertEqual(totals[key]?.output, 20)
        XCTAssertEqual(totals[key]?.cacheRead, 4)
        XCTAssertEqual(totals[key]?.cacheCreation, 2)
    }

    func testDedupesPromptID() {
        var totals: [DayModelKey: TokenCounts] = [:]
        var seen = Set<String>()
        XCTAssertEqual(GrokLineParser.consume(turn, into: &totals, seen: &seen, timeZone: utc), 1)
        XCTAssertEqual(GrokLineParser.consume(turn, into: &totals, seen: &seen, timeZone: utc), 0)
        XCTAssertEqual(totals.values.first?.output, 20)
    }

    func testScannerReadsUpdatesFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = dir.appendingPathComponent("sessions/proj/sid")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try (turn + "\n").write(to: nested.appendingPathComponent("updates.jsonl"), atomically: true, encoding: .utf8)
        let scanner = GrokHistoryScanner(root: dir, timeZone: utc)
        let now = DateParsing.parse("2026-08-27T12:00:00Z")!
        let totals = scanner.scan(now: now)
        XCTAssertEqual(scanner.newEventsInLastScan, 1)
        XCTAssertEqual(totals[DayModelKey(day: "2026-08-27", model: "grok-4.6-build")]?.output, 20)
        try? FileManager.default.removeItem(at: dir)
    }
}
