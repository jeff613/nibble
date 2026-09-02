import XCTest
@testable import NibbleCore

final class ProviderTests: XCTestCase {
    func testDisplayNames() {
        XCTAssertEqual(Provider.claude.displayName, "Claude")
        XCTAssertEqual(Provider.codex.displayName, "Codex")
        XCTAssertEqual(Provider.grok.displayName, "Grok")
    }

    func testBarLabels() {
        XCTAssertEqual(Provider.claude.barLabel, "claude")
        XCTAssertEqual(Provider.codex.barLabel, "gpt")
        XCTAssertEqual(Provider.grok.barLabel, "grok")
    }

    func testOptOutKeysAreStable() {
        XCTAssertEqual(Provider.claude.optOutKey, "optOut.claude")
        XCTAssertEqual(Provider.codex.optOutKey, "optOut.codex")
        XCTAssertEqual(Provider.grok.optOutKey, "optOut.grok")
    }

    func testFallbackKeepsSelectionWhenStillConnected() {
        XCTAssertEqual(
            Provider.fallback(selected: .codex, connected: [.claude, .codex]),
            .codex)
    }

    func testFallbackOrderIsClaudeThenCodexThenGrok() {
        XCTAssertEqual(
            Provider.fallback(selected: .codex, connected: [.grok, .claude]),
            .claude)
        XCTAssertEqual(
            Provider.fallback(selected: .claude, connected: [.grok]),
            .grok)
        XCTAssertNil(Provider.fallback(selected: .claude, connected: []))
    }
}
