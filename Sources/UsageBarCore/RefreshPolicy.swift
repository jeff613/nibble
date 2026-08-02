import Foundation

/// Decides when to spend a request on the usage endpoint.
///
/// The endpoint enforces an hourly budget and answers a breach with a
/// `Retry-After` measured in tens of minutes, so requests are spent only when
/// they can actually reveal a change. Quota moves when you use Claude — which
/// the log watcher already tells us — or when a window resets, which we can
/// predict exactly. The timer below is only a backstop for usage that never
/// touches this Mac, such as claude.ai in a browser or a second machine.
public enum RefreshPolicy {
    /// Backstop while Claude Code has been active recently.
    public static let activeInterval: TimeInterval = 120
    /// Backstop when nothing local is happening. Catches off-machine usage.
    public static let idleHeartbeat: TimeInterval = 900
    /// How recently Claude Code must have run to count as active.
    public static let activityWindow: TimeInterval = 300
    /// Wait this long after a window resets before reading the new value.
    public static let resetGrace: TimeInterval = 5

    /// Hard floor between network calls, whatever triggered them. The file
    /// watcher fires continuously while Claude Code writes logs, so without
    /// this the app would hammer the endpoint and get rate limited.
    public static let minimumSpacing: TimeInterval = 60

    public static func interval(lastActivity: Date?, now: Date) -> TimeInterval {
        guard let last = lastActivity, now.timeIntervalSince(last) < activityWindow else {
            return idleHeartbeat
        }
        return activeInterval
    }

    /// True when enough time has passed since the last network call.
    public static func shouldFetch(lastFetch: Date?, now: Date) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= minimumSpacing
    }

    /// Seconds until the next scheduled poll: the backstop interval, pulled
    /// earlier if a quota window resets before then (so the jump to 0% shows up
    /// immediately rather than after a stale wait).
    public static func nextWakeUp(lastActivity: Date?, resets: [Date], now: Date) -> TimeInterval {
        let backstop = interval(lastActivity: lastActivity, now: now)
        guard let nextReset = resets.filter({ $0 > now }).min() else { return backstop }
        let untilReset = nextReset.timeIntervalSince(now) + resetGrace
        return max(minimumSpacing, min(backstop, untilReset))
    }

    /// How long to wait after a 429.
    ///
    /// The server's `Retry-After` is authoritative and must be honoured in full —
    /// it has been observed at ~2000s, so clamping it low just re-trips the limit
    /// and can extend the penalty. The 2-hour ceiling only guards against a
    /// nonsense value locking the app out indefinitely.
    public static func backoff(consecutiveRateLimits: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter, retryAfter > 0 { return min(retryAfter, 7200) }
        // No header: assume a fixed hourly window and start well back.
        let exponent = max(0, consecutiveRateLimits - 1)
        let seconds = 300 * pow(2, Double(min(exponent, 6)))
        return min(seconds, 3600)
    }
}
