import XCTest
@testable import NibbleCore

final class ProviderTests: XCTestCase {
    func testDisplayNames() {
        XCTAssertEqual(Provider.claude.displayName, "Claude")
        XCTAssertEqual(Provider.codex.displayName, "Codex")
        XCTAssertEqual(Provider.grok.displayName, "Grok")
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

    func testConsentKeysAreStable() {
        XCTAssertEqual(Provider.claude.consentKey, "hasConnectedClaudeCodeLogin")
        XCTAssertEqual(Provider.codex.consentKey, "hasConnectedCodexLogin")
        XCTAssertEqual(Provider.grok.consentKey, "hasConnectedGrokLogin")
    }
}
