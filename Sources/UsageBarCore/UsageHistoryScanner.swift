import Foundation

/// Scans `~/.claude/projects/**/*.jsonl` for per-message token usage.
/// Incremental: each file is read only from the last consumed byte offset.
public final class UsageHistoryScanner {
    let root: URL
    let timeZone: TimeZone

    private var offsets: [String: UInt64] = [:]
    private var totals: [DayModelKey: TokenCounts] = [:]
    private var seen = Set<String>()

    public init(root: URL, timeZone: TimeZone = .current) {
        self.root = root
        self.timeZone = timeZone
    }

    public func scan(now: Date = Date()) -> [DayModelKey: TokenCounts] {
        let cutoff = now.addingTimeInterval(-8 * 86400)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard let mtime = values?.contentModificationDate, mtime >= cutoff else { continue }

            let size = UInt64(values?.fileSize ?? 0)
            let path = url.path
            var offset = offsets[path] ?? 0
            if size < offset { offset = 0 }        // truncated or rotated: re-read fully
            guard size > offset else { continue }  // nothing appended since last scan

            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.readToEnd(),
                  let text = String(data: data, encoding: .utf8) else { continue }

            let events = text.split(separator: "\n").compactMap { UsageLineParser.parse(String($0)) }
            UsageAggregator.fold(events: events, into: &totals, seen: &seen, timeZone: timeZone)
            offsets[path] = size
        }

        // Day keys are zero-padded yyyy-MM-dd, so string comparison orders them correctly.
        let minDay = UsageAggregator.dayKey(for: now.addingTimeInterval(-6 * 86400), timeZone: timeZone)
        return totals.filter { $0.key.day >= minDay }
    }
}
