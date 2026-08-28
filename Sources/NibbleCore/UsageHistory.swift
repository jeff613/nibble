import Foundation

public struct UsageEvent: Equatable, Sendable {
    public var timestamp: Date
    public var model: String
    public var dedupeKey: String?
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int
}

public enum UsageLineParser {
    public static func parse(_ line: String) -> UsageEvent? {
        guard let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["type"] as? String == "assistant",
              let ts = (root["timestamp"] as? String).flatMap(DateParsing.parse),
              let message = root["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return nil }

        let model = message["model"] as? String ?? "unknown"
        let messageID = message["id"] as? String
        let requestID = root["requestId"] as? String
        // Streamed chunks can repeat usage for the same message; key on both IDs.
        let dedupeKey = messageID.map { "\($0):\(requestID ?? "")" }

        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }

        return UsageEvent(timestamp: ts, model: model, dedupeKey: dedupeKey,
                          input: count("input_tokens"),
                          output: count("output_tokens"),
                          cacheCreation: count("cache_creation_input_tokens"),
                          cacheRead: count("cache_read_input_tokens"))
    }
}

public struct DayModelKey: Hashable, Sendable {
    public var day: String
    public var model: String
    public init(day: String, model: String) {
        self.day = day
        self.model = model
    }
}

public struct TokenCounts: Equatable, Sendable {
    public var input = 0
    public var output = 0
    public var cacheCreation = 0
    public var cacheRead = 0

    public init() {}

    public var total: Int { input + output + cacheCreation + cacheRead }

    public mutating func add(_ e: UsageEvent) {
        input += e.input
        output += e.output
        cacheCreation += e.cacheCreation
        cacheRead += e.cacheRead
    }

    public mutating func add(_ other: TokenCounts) {
        input += other.input
        output += other.output
        cacheCreation += other.cacheCreation
        cacheRead += other.cacheRead
    }
}

public enum HistoryMerge {
    public static func union(_ parts: [[DayModelKey: TokenCounts]]) -> [DayModelKey: TokenCounts] {
        var out: [DayModelKey: TokenCounts] = [:]
        for part in parts {
            for (key, counts) in part {
                out[key, default: TokenCounts()].add(counts)
            }
        }
        return out
    }
}

/// One stacked-bar segment: a family's token total for one day.
public struct DayFamilyTotal: Equatable, Sendable {
    public let day: String
    public let family: String
    public let tokens: Int
}

public enum UsageAggregator {
    /// Collapses per-model day totals into per-family chart segments, days
    /// ascending and families in `ModelPalette` order within each day — the
    /// source dictionary has no order, and a chart fed from it directly would
    /// stack each day's bar differently.
    ///
    /// When `days` is non-empty, missing dates are kept as 0-token segments so
    /// a 7-day chart does not skip a column. An empty `totals` stays empty
    /// (the panel's "no logs" state) rather than rendering a week of zeros.
    public static func dayFamilyTotals(_ totals: [DayModelKey: TokenCounts],
                                       days: [String] = []) -> [DayFamilyTotal] {
        var merged: [DayModelKey: Int] = [:]
        for (key, counts) in totals {
            let name = DayModelKey(day: key.day, model: ModelPalette.shortName(for: key.model))
            merged[name, default: 0] += counts.total
        }
        var segments = merged
            .map { DayFamilyTotal(day: $0.key.day, family: $0.key.model, tokens: $0.value) }
        if !segments.isEmpty, !days.isEmpty {
            let present = Set(segments.map(\.day))
            let names = Set(segments.map(\.family))
            let family = names.min { ModelPalette.legendIndex(of: $0) < ModelPalette.legendIndex(of: $1) }
                ?? "other"
            for day in days where !present.contains(day) {
                segments.append(DayFamilyTotal(day: day, family: family, tokens: 0))
            }
        }
        return segments.sorted {
            ($0.day, ModelPalette.legendIndex(of: $0.family), $0.family)
                < ($1.day, ModelPalette.legendIndex(of: $1.family), $1.family)
        }
    }

    public static func dayKey(for date: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// The 7 local calendar days ending on `date`, oldest first (`yyyy-MM-dd`).
    public static func lastSevenDays(endingOn date: Date, timeZone: TimeZone) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: date)
        return (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset - 6, to: start)!
            return dayKey(for: day, timeZone: timeZone)
        }
    }

    /// Folds events into `totals`, skipping ones already seen.
    /// Returns how many were genuinely new — the signal for "quota just moved".
    @discardableResult
    public static func fold(events: [UsageEvent], into totals: inout [DayModelKey: TokenCounts],
                            seen: inout Set<String>, timeZone: TimeZone) -> Int {
        var accepted = 0
        for e in events {
            if let key = e.dedupeKey {
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            let key = DayModelKey(day: dayKey(for: e.timestamp, timeZone: timeZone), model: e.model)
            totals[key, default: TokenCounts()].add(e)
            accepted += 1
        }
        return accepted
    }
}
