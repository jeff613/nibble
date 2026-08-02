import Foundation

/// Fixed model-family colours.
///
/// Charts must never assign colours positionally: which families appear varies
/// week to week, so a positional scale would give Opus one colour today and a
/// different one tomorrow. Every family's colour is pinned here instead, and
/// looked up by name.
public enum ModelPalette {
    /// Canonical family order — also the legend order.
    public static let families = ["fable", "opus", "sonnet", "mythos", "haiku", "other"]

    private static let hexes: [String: String] = [
        "fable": "E8833A",   // orange
        "opus": "3B82F6",    // blue
        "sonnet": "22A06B",  // green
        "mythos": "A855F7",  // purple
        "haiku": "EC4899",   // pink
        "other": "8A8A8E",   // grey
    ]

    /// Maps a full model ID (`claude-fable-5`, `claude-haiku-4-5-20251001`)
    /// to its family. Unknown models fall back to `other` rather than vanishing.
    public static func family(for modelID: String) -> String {
        let id = modelID.lowercased()
        for family in families where family != "other" && id.contains(family) {
            return family
        }
        return "other"
    }

    public static func hex(for family: String) -> String {
        hexes[family] ?? hexes["other"]!
    }

    /// The families present in `modelIDs`, in canonical order — so the legend
    /// is stable and only lists what's actually on the chart.
    public static func presentFamilies(in modelIDs: some Collection<String>) -> [String] {
        let present = Set(modelIDs.map(family(for:)))
        return families.filter(present.contains)
    }
}
