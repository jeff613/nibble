import Foundation

public enum GrokLineParser {
    @discardableResult
    public static func consume(_ line: String, into totals: inout [DayModelKey: TokenCounts],
                               seen: inout Set<String>, timeZone: TimeZone) -> Int {
        guard let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return 0
        }
        let params = root["params"] as? [String: Any] ?? [:]
        let update = params["update"] as? [String: Any] ?? [:]
        guard update["sessionUpdate"] as? String == "turn_completed" else { return 0 }
        let promptID = update["prompt_id"] as? String ?? ""
        guard !promptID.isEmpty, !seen.contains(promptID) else { return 0 }
        seen.insert(promptID)

        let stamp: Date
        if let ms = ((params["_meta"] as? [String: Any])?["agentTimestampMs"] as? NSNumber)?.doubleValue {
            stamp = Date(timeIntervalSince1970: ms / 1000)
        } else if let unix = (root["timestamp"] as? NSNumber)?.doubleValue {
            stamp = Date(timeIntervalSince1970: unix)
        } else {
            stamp = Date()
        }
        let day = UsageAggregator.dayKey(for: stamp, timeZone: timeZone)

        let modelUsage = ((update["usage"] as? [String: Any])?["modelUsage"] as? [String: Any]) ?? [:]
        var accepted = 0
        for (model, raw) in modelUsage {
            guard UsageModelFilter.isUserFacing(model) else { continue }
            guard let usage = raw as? [String: Any] else { continue }
            func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
            let key = DayModelKey(day: day, model: model)
            var counts = totals[key, default: TokenCounts()]
            counts.input += count("inputTokens")
            counts.output += count("outputTokens")
            counts.cacheCreation += count("cacheCreationTokens")
            counts.cacheRead += count("cachedReadTokens")
            totals[key] = counts
            accepted += 1
        }
        return accepted
    }
}

public final class GrokHistoryScanner {
    let root: URL
    let timeZone: TimeZone

    private var offsets: [String: UInt64] = [:]
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
            guard url.lastPathComponent == "updates.jsonl" else { continue }
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

            for line in text.split(separator: "\n") {
                newEventsInLastScan += GrokLineParser.consume(
                    String(line), into: &totals, seen: &seen, timeZone: timeZone)
            }
            offsets[path] = size
        }

        let minDay = UsageAggregator.lastSevenDays(endingOn: now, timeZone: timeZone)[0]
        return totals.filter { $0.key.day >= minDay }
    }
}
