import Foundation

public enum Provider: String, CaseIterable, Sendable {
    case claude, codex, grok

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .grok: return "Grok"
        }
    }

    public var consentKey: String {
        switch self {
        case .claude: return "hasConnectedClaudeCodeLogin"
        case .codex: return "hasConnectedCodexLogin"
        case .grok: return "hasConnectedGrokLogin"
        }
    }

    public static func fallback(selected: Provider, connected: Set<Provider>) -> Provider? {
        if connected.contains(selected) { return selected }
        for p in [Provider.claude, .codex, .grok] where connected.contains(p) { return p }
        return nil
    }
}
