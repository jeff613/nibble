import Foundation

/// Polls fast while you're actively burning quota, slow when idle — but never
/// faster than `minimumSpacing`, and backs off hard when the server pushes back.
public enum RefreshPolicy {
    public static let activeInterval: TimeInterval = 15
    public static let idleInterval: TimeInterval = 60
    public static let activityWindow: TimeInterval = 300

    /// Hard floor between network calls, whatever triggered them. The file
    /// watcher fires continuously while Claude Code writes logs, so without
    /// this the app would hammer the endpoint and get rate limited.
    public static let minimumSpacing: TimeInterval = 15

    public static func interval(lastActivity: Date?, maxPercent: Double, now: Date) -> TimeInterval {
        if let last = lastActivity, now.timeIntervalSince(last) < activityWindow {
            return activeInterval
        }
        return maxPercent >= 70 ? activeInterval : idleInterval
    }

    /// True when enough time has passed since the last network call.
    public static func shouldFetch(lastFetch: Date?, now: Date) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= minimumSpacing
    }

    /// How long to wait after a 429. Honours the server's `Retry-After` when it
    /// sends one; otherwise doubles from 60s, capped at 10 minutes.
    public static func backoff(consecutiveRateLimits: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter, retryAfter > 0 { return min(retryAfter, 900) }
        let exponent = max(0, consecutiveRateLimits - 1)
        let seconds = 60 * pow(2, Double(min(exponent, 8)))
        return min(seconds, 600)
    }
}
