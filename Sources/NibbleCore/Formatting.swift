import Foundation

public enum Severity: Int, Comparable, Sendable {
    case normal, warning, critical
    public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
}

public enum Formatting {
    static let kindOrder = [
        "session": 0, "weekly_all": 1, "weekly_scoped": 2,
        "weekly": 3, "monthly": 4, "credits": 5,
    ]

    public static func sorted(_ windows: [LimitWindow]) -> [LimitWindow] {
        windows.sorted { (kindOrder[$0.kind] ?? 99) < (kindOrder[$1.kind] ?? 99) }
    }

    public static func shortLabel(_ w: LimitWindow) -> String {
        switch w.kind {
        case "session": return "5h"
        case "weekly_all", "weekly": return "wk"
        case "weekly_scoped": return w.modelName.map { String($0.prefix(1)) } ?? "m"
        case "monthly": return "mo"
        case "credits": return "cr"
        default: return String(w.kind.prefix(2))
        }
    }

    public static func barText(_ windows: [LimitWindow]) -> String {
        guard !windows.isEmpty else { return "—" }
        return sorted(windows)
            .map { "\(shortLabel($0)) \(Int($0.percent.rounded()))%" }
            .joined(separator: " · ")
    }

    public static func severity(_ windows: [LimitWindow]) -> Severity {
        let worst = windows.map(\.percent).max() ?? 0
        if worst >= 90 { return .critical }
        if worst >= 75 { return .warning }
        return .normal
    }

    /// Compact token counts for chart axes: 45K, 3M, 1.2B — never `3.0E8`.
    public static func compactCount(_ value: Double) -> String {
        let magnitude = abs(value)
        let (scaled, suffix): (Double, String)
        switch magnitude {
        case 1_000_000_000...: (scaled, suffix) = (value / 1_000_000_000, "B")
        case 1_000_000...: (scaled, suffix) = (value / 1_000_000, "M")
        case 1_000...: (scaled, suffix) = (value / 1_000, "K")
        default: return String(Int(value.rounded()))
        }
        // One decimal only when it adds information: 1.2M, but 300M not 300.0M.
        let rounded = (scaled * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded))\(suffix)"
            : String(format: "%.1f%@", rounded, suffix)
    }

    /// Human duration for short waits: "45s", "12m", "1h 5m".
    public static func duration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "0s" }
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    public static func countdown(until: Date, now: Date) -> String {
        let seconds = until.timeIntervalSince(now)
        guard seconds > 0 else { return "resetting…" }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "resets in <1m" }
        let hours = minutes / 60
        // Weekly windows run to ~168h; minutes are noise at that scale.
        if hours >= 24 {
            let days = hours / 24
            let remainder = hours % 24
            return remainder == 0
                ? "resets in \(days)d"
                : "resets in \(days)d \(remainder)h"
        }
        let remainder = minutes % 60
        return hours > 0 ? "resets in \(hours)h \(remainder)m" : "resets in \(remainder)m"
    }
}
