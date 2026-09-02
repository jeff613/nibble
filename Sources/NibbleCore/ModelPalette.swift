import Foundation

/// Fixed colours keyed by short model name.
///
/// Charts must never assign colours positionally: which models appear varies
/// week to week, so a positional scale would give Opus one colour today and a
/// different one tomorrow. Every name's colour is pinned or hashed here.
public enum ModelPalette {
    /// Canonical Claude family order, used to sort those models in the legend.
    public static let families = ["fable", "opus", "sonnet", "mythos", "haiku", "other"]

    private static let hexes: [String: String] = [
        "fable": "E8833A",
        "fable-5": "E8833A",
        "opus": "3B82F6",
        "opus-5": "3B82F6",
        "opus-4-8": "8B5CF6",
        "sonnet": "22A06B",
        "sonnet-5": "22A06B",
        "sonnet-4-5": "22A06B",
        "mythos": "A855F7",
        "mythos-5": "A855F7",
        "haiku": "EC4899",
        "haiku-4-5": "EC4899",
        "gpt-5.6-sol": "DC2626",
        "gpt-5.6-terra": "DB2777",
        "gpt-5.6-luna": "CA8A04",
        "gpt-5.6": "7C3AED",
        "gpt-5.5": "0D9488",
        "gpt-5.4": "C026D3",
        "gpt-5": "475569",
        "grok-4.6": "06B6D4",
        "grok-4.5": "0EA5E9",
        "grok-4": "0284C7",
        "other": "8A8A8E",
    ]

    private static let hashPalette: [String] = [
        "E8833A", "3B82F6", "22A06B", "A855F7", "EC4899", "10A37F", "1DA1F2", "8A8A8E",
    ]

    /// Maps a full model ID to a short legend name (`opus-5`, `grok-4.6`).
    public static func shortName(for modelID: String) -> String {
        var id = modelID.lowercased()
        if id.hasPrefix("claude-") { id.removeFirst("claude-".count) }
        if id.hasSuffix("-build") { id.removeLast("-build".count) }
        if let range = id.range(of: #"-\d{8}$"#, options: .regularExpression) {
            id.removeSubrange(range)
        }
        return id
    }

    /// Maps a full model ID (`claude-fable-5`, `claude-haiku-4-5-20251001`)
    /// to its family. Unknown models fall back to `other`.
    public static func family(for modelID: String) -> String {
        let id = modelID.lowercased()
        for family in families where family != "other" && id.contains(family) {
            return family
        }
        return "other"
    }

    public static func hex(for name: String) -> String {
        if let pinned = hexes[name] { return pinned }
        let sum = name.utf8.reduce(0) { ($0 &+ Int($1)) }
        return hashPalette[abs(sum) % hashPalette.count]
    }

    /// Short names present in `modelIDs`, in legend order: Claude families,
    /// then gpt-*, then grok-*, then leftovers alphabetically.
    public static func present(in modelIDs: some Collection<String>) -> [String] {
        Array(Set(modelIDs.map(shortName(for:)))).sorted(by: legendOrdered)
    }

    /// The families present in `modelIDs`, in canonical order.
    public static func presentFamilies(in modelIDs: some Collection<String>) -> [String] {
        let present = Set(modelIDs.map(family(for:)))
        return families.filter(present.contains)
    }

    static func legendIndex(of name: String) -> Int {
        let claude = ["fable", "opus", "sonnet", "mythos", "haiku"]
        if let i = claude.firstIndex(where: { name == $0 || name.hasPrefix($0 + "-") }) {
            return i
        }
        if name.hasPrefix("gpt") { return 100 }
        if name.hasPrefix("grok") { return 200 }
        return 300
    }

    private static func legendOrdered(_ a: String, _ b: String) -> Bool {
        let ia = legendIndex(of: a), ib = legendIndex(of: b)
        if ia != ib { return ia < ib }
        return a < b
    }
}
