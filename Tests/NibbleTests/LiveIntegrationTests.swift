import XCTest
@testable import NibbleCore

/// End-to-end check against the real Claude Code login and the real usage endpoint.
///
/// Skipped unless `NIBBLE_INTEGRATION=1` is set, because it needs a signed-in
/// Claude Code and network access. Run it with:
///
///     NIBBLE_INTEGRATION=1 make test
///
final class LiveIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NIBBLE_INTEGRATION"] == "1",
                          "set NIBBLE_INTEGRATION=1 to run live checks")
    }

    func testReadsRealLoginAndFetchesLiveQuota() async throws {
        let credentials = ClaudeCodeCredentials()

        let token: String
        do {
            token = try credentials.readToken()
        } catch let error as ClaudeCodeCredentials.LookupError {
            return XCTFail("credential read failed: \(error.errorDescription ?? "?")")
        }
        XCTAssertFalse(token.isEmpty)

        let client = ClaudeUsageClient { reload in try credentials.readToken(reload: reload) }
        let windows = try await client.fetchUsage()

        XCTAssertFalse(windows.isEmpty, "expected at least one limit window")
        for window in windows {
            XCTAssertFalse(window.kind.isEmpty)
            XCTAssertTrue((0...100).contains(window.percent),
                          "\(window.kind) percent out of range: \(window.percent)")
        }
        // Every window the endpoint reports should render without crashing.
        let bar = Formatting.barText(windows)
        XCTAssertNotEqual(bar, "—")
        print("LIVE bar text: \(bar)")
        print("LIVE windows: \(windows.map { "\($0.kind)=\(Int($0.percent))%" }.joined(separator: " "))")
    }

    func testScansRealHistoryAndPrices() throws {
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: projects.path),
                          "no ~/.claude/projects on this machine")

        let totals = UsageHistoryScanner(root: projects).scan()
        let tokens = totals.values.reduce(0) { $0 + $1.total }
        print("LIVE history: \(totals.count) day/model buckets, \(tokens) tokens, "
              + String(format: "$%.2f", Pricing.totalCost(totals)))
        XCTAssertGreaterThan(totals.count, 0, "expected recent Claude Code activity")
    }
}
