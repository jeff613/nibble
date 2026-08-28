import Foundation

public enum CodexLineParser {
    /// Returns how many new token_count events were accepted.
    @discardableResult
    public static func consume(_ line: String, model: inout String,
                               into totals: inout [DayModelKey: TokenCounts],
                               seen: inout Set<String>, timeZone: TimeZone) -> Int {
        guard let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return 0
        }
        let type = root["type"] as? String
        let payload = root["payload"] as? [String: Any] ?? [:]

        if type == "turn_context", let id = payload["model"] as? String, !id.isEmpty {
            model = id
            return 0
        }

        guard type == "event_msg", payload["type"] as? String == "token_count" else { return 0 }
        let ts = root["timestamp"] as? String ?? ""
        let ordinal = (root["ordinal"] as? NSNumber)?.stringValue ?? ""
        let dedupe = "\(ts):\(ordinal)"
        if seen.contains(dedupe) { return 0 }
        seen.insert(dedupe)

        let usage = (payload["info"] as? [String: Any])?["last_token_usage"] as? [String: Any] ?? [:]
        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        let stamp = (root["timestamp"] as? String).flatMap(DateParsing.parse) ?? Date()
        let key = DayModelKey(day: UsageAggregator.dayKey(for: stamp, timeZone: timeZone), model: model)
        var counts = totals[key, default: TokenCounts()]
        counts.input += count("input_tokens")
        counts.output += count("output_tokens")
        counts.cacheCreation += count("cache_write_input_tokens")
        counts.cacheRead += count("cached_input_tokens")
        totals[key] = counts
        return 1
    }
}

public final class CodexHistoryScanner {
    let root: URL
    let timeZone: TimeZone

    private var offsets: [String: UInt64] = [:]
    private var models: [String: String] = [:]
    private var totals: [DayModelKey: TokenCounts] = [:]
    private var seen = Set<String>()
    public private(set) var newEventsInLastScan = 0

    public init(root: URL, timeZone: TimeZone = .current) {
        self.root = root
        self.timeZone = timeZone
    }

    public func scan(now: Date = Date()) -> [DayModelKey: TokenCounts] {
        newEventsInLastScan = 0
        let cutoff = now.addingTimeInterval(-8 * 86400)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("rollout-") else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard let mtime = values?.contentModificationDate, mtime >= cutoff else { continue }

            let size = UInt64(values?.fileSize ?? 0)
            let path = url.path
            var offset = offsets[path] ?? 0
            if size < offset { offset = 0 }
            guard size > offset else { continue }

            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.readToEnd(),
                  let text = String(data: data, encoding: .utf8) else { continue }

            var model = models[path] ?? "unknown"
            for line in text.split(separator: "\n") {
                newEventsInLastScan += CodexLineParser.consume(
                    String(line), model: &model, into: &totals, seen: &seen, timeZone: timeZone)
            }
            models[path] = model
            offsets[path] = size
        }

        let minDay = UsageAggregator.lastSevenDays(endingOn: now, timeZone: timeZone)[0]
        return totals.filter { $0.key.day >= minDay }
    }
}
