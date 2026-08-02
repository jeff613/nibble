import XCTest
@testable import UsageBarCore

final class ScannerTests: XCTestCase {
    var dir: URL!
    let utc = TimeZone(identifier: "UTC")!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("proj"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func line(day: String, model: String = "claude-fable-5", msg: String, out: Int) -> String {
        #"{"type":"assistant","timestamp":"\#(day)T10:00:00Z","requestId":"r","message":{"id":"\#(msg)","model":"\#(model)","usage":{"input_tokens":1,"output_tokens":\#(out),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
    }

    @discardableResult
    func write(_ content: String, to name: String) throws -> URL {
        let url = dir.appendingPathComponent("proj/\(name)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testScansAndFiltersToTrailing7Days() throws {
        let now = DateParsing.parse("2026-08-01T12:00:00Z")!
        try write([line(day: "2026-08-01", msg: "a", out: 5),
                   line(day: "2026-07-20", msg: "b", out: 7)].joined(separator: "\n"),
                  to: "s.jsonl")
        let scanner = UsageHistoryScanner(root: dir, timeZone: utc)
        let totals = scanner.scan(now: now)
        XCTAssertEqual(totals[DayModelKey(day: "2026-08-01", model: "claude-fable-5")]?.output, 5)
        XCTAssertNil(totals[DayModelKey(day: "2026-07-20", model: "claude-fable-5")])
    }

    func testIncrementalAppendOnlyReadsNewLines() throws {
        let now = DateParsing.parse("2026-08-01T12:00:00Z")!
        let url = try write(line(day: "2026-08-01", msg: "a", out: 5) + "\n", to: "s.jsonl")
        let scanner = UsageHistoryScanner(root: dir, timeZone: utc)
        _ = scanner.scan(now: now)

        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(Data((line(day: "2026-08-01", msg: "b", out: 3) + "\n").utf8))
        try handle.close()

        let totals = scanner.scan(now: now)
        XCTAssertEqual(totals[DayModelKey(day: "2026-08-01", model: "claude-fable-5")]?.output, 8)
    }

    // The refresh scheme spends a network request only when this is > 0,
    // so a false positive here means wasted quota against the rate limit.
    func testReportsNewEventCountPerScan() throws {
        let now = DateParsing.parse("2026-08-01T12:00:00Z")!
        let url = try write(line(day: "2026-08-01", msg: "a", out: 5) + "\n", to: "s.jsonl")
        let scanner = UsageHistoryScanner(root: dir, timeZone: utc)

        _ = scanner.scan(now: now)
        XCTAssertEqual(scanner.newEventsInLastScan, 1)

        // Rescan with nothing appended: no new usage, so no refresh warranted.
        _ = scanner.scan(now: now)
        XCTAssertEqual(scanner.newEventsInLastScan, 0)

        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(Data((line(day: "2026-08-01", msg: "b", out: 3) + "\n").utf8))
        try handle.close()

        _ = scanner.scan(now: now)
        XCTAssertEqual(scanner.newEventsInLastScan, 1)
    }

    func testDuplicateEventsDoNotCountAsNew() throws {
        let now = DateParsing.parse("2026-08-01T12:00:00Z")!
        let duplicate = line(day: "2026-08-01", msg: "a", out: 5)
        try write([duplicate, duplicate].joined(separator: "\n"), to: "s.jsonl")
        let scanner = UsageHistoryScanner(root: dir, timeZone: utc)
        _ = scanner.scan(now: now)
        XCTAssertEqual(scanner.newEventsInLastScan, 1)
    }

    func testRescanWithoutChangesIsStable() throws {
        let now = DateParsing.parse("2026-08-01T12:00:00Z")!
        try write(line(day: "2026-08-01", msg: "a", out: 5), to: "s.jsonl")
        let scanner = UsageHistoryScanner(root: dir, timeZone: utc)
        let first = scanner.scan(now: now)
        let second = scanner.scan(now: now)
        XCTAssertEqual(first, second)
    }
}
