import Foundation

/// Polls fast while you're actively burning quota, slow when idle — but never
/// faster than `minimumSpacing`, and backs off hard when the server pushes back.
public enum RefreshPolicy {
    /// The endpoint enforces an hourly budget and answers a breach with a
    /// `Retry-After` measured in *tens of minutes*, so being greedy costs far
    /// more freshness than it buys. These intervals keep the worst case at
    /// 60 requests/hour and the typical case well under it.
    public static let nearLimitInterval: TimeInterval = 60
    public static let activeInterval: TimeInterval = 120
    public static let idleInterval: TimeInterval = 300
    public static let activityWindow: TimeInterval = 300

    /// Percentage past which freshness matters enough to poll every minute.
    public static let nearLimitThreshold: Double = 80

    /// Hard floor between network calls, whatever triggered them. The file
    /// watcher fires continuously while Claude Code writes logs, so without
    /// this the app would hammer the endpoint and get rate limited.
    public static let minimumSpacing: TimeInterval = 60

    public static func interval(lastActivity: Date?, maxPercent: Double, now: Date) -> TimeInterval {
        if maxPercent >= nearLimitThreshold { return nearLimitInterval }
        if let last = lastActivity, now.timeIntervalSince(last) < activityWindow {
            return activeInterval
        }
        return idleInterval
    }

    /// True when enough time has passed since the last network call.
    public static func shouldFetch(lastFetch: Date?, now: Date) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= minimumSpacing
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
