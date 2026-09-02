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

    /// Compact status-item prefix. Codex is labeled `gpt` because that is the
    /// model family the quota belongs to.
    public var barLabel: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "gpt"
        case .grok: return "grok"
        }
    }

    public var optOutKey: String { "optOut.\(rawValue)" }

    public static func fallback(selected: Provider, connected: Set<Provider>) -> Provider? {
        if connected.contains(selected) { return selected }
        for p in [Provider.claude, .codex, .grok] where connected.contains(p) { return p }
        return nil
    }
}
