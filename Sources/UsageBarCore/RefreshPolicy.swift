import Foundation

/// Polls fast while you're actively burning quota, slow when idle.
public enum RefreshPolicy {
    public static let activeInterval: TimeInterval = 10
    public static let idleInterval: TimeInterval = 60
    public static let activityWindow: TimeInterval = 300

    public static func interval(lastActivity: Date?, maxPercent: Double, now: Date) -> TimeInterval {
        if let last = lastActivity, now.timeIntervalSince(last) < activityWindow {
            return activeInterval
        }
        return maxPercent >= 70 ? activeInterval : idleInterval
    }
}
