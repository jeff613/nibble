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
}

public enum UsageAggregator {
    public static func dayKey(for date: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func fold(events: [UsageEvent], into totals: inout [DayModelKey: TokenCounts],
                            seen: inout Set<String>, timeZone: TimeZone) {
        for e in events {
            if let key = e.dedupeKey {
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            let key = DayModelKey(day: dayKey(for: e.timestamp, timeZone: timeZone), model: e.model)
            totals[key, default: TokenCounts()].add(e)
        }
    }
}
