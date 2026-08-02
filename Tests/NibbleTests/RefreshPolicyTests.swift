import XCTest
@testable import NibbleCore

final class RefreshPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Poll interval

    func testActiveWhenRecentActivity() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: now.addingTimeInterval(-60), now: now),
                       RefreshPolicy.activeInterval)
    }

    func testIdleHeartbeatOtherwise() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: now.addingTimeInterval(-600), now: now),
                       RefreshPolicy.idleHeartbeat)
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: nil, now: now),
                       RefreshPolicy.idleHeartbeat)
    }

    func testNoIntervalBeatsTheFloor() {
        for interval in [RefreshPolicy.activeInterval, RefreshPolicy.idleHeartbeat] {
            XCTAssertGreaterThanOrEqual(interval, RefreshPolicy.minimumSpacing)
        }
    }

    func testWorstCaseStaysUnderSixtyRequestsPerHour() {
        XCTAssertLessThanOrEqual(3600 / RefreshPolicy.minimumSpacing, 60)
    }

    // MARK: Reset-aware scheduling

    func testWakesJustAfterAWindowResets() {
        let reset = now.addingTimeInterval(90)
        let wake = RefreshPolicy.nextWakeUp(lastActivity: now, resets: [reset], now: now)
        XCTAssertEqual(wake, 90 + RefreshPolicy.resetGrace)
    }

    func testUsesEarliestFutureReset() {
        let resets = [now.addingTimeInterval(300), now.addingTimeInterval(80)]
        let wake = RefreshPolicy.nextWakeUp(lastActivity: now, resets: resets, now: now)
        XCTAssertEqual(wake, 80 + RefreshPolicy.resetGrace)
    }

    func testIgnoresResetsAlreadyPassed() {
        let stale = now.addingTimeInterval(-600)
        let wake = RefreshPolicy.nextWakeUp(lastActivity: now, resets: [stale], now: now)
        XCTAssertEqual(wake, RefreshPolicy.activeInterval)
    }

    func testDistantResetDoesNotDelayTheBackstop() {
        let far = now.addingTimeInterval(100_000)
        let wake = RefreshPolicy.nextWakeUp(lastActivity: nil, resets: [far], now: now)
        XCTAssertEqual(wake, RefreshPolicy.idleHeartbeat)
    }

    func testImminentResetStillRespectsTheFloor() {
        let imminent = now.addingTimeInterval(2)
        let wake = RefreshPolicy.nextWakeUp(lastActivity: now, resets: [imminent], now: now)
        XCTAssertEqual(wake, RefreshPolicy.minimumSpacing)
    }

    func testNoResetsFallsBackToInterval() {
        XCTAssertEqual(RefreshPolicy.nextWakeUp(lastActivity: nil, resets: [], now: now),
                       RefreshPolicy.idleHeartbeat)
    }

    // MARK: Minimum spacing

    func testFirstFetchIsAllowed() {
        XCTAssertTrue(RefreshPolicy.shouldFetch(lastFetch: nil, now: now))
    }

    func testFetchBlockedInsideTheFloor() {
        let recent = now.addingTimeInterval(-1)
        XCTAssertFalse(RefreshPolicy.shouldFetch(lastFetch: recent, now: now))
    }

    func testFetchAllowedOnceFloorElapses() {
        let old = now.addingTimeInterval(-RefreshPolicy.minimumSpacing)
        XCTAssertTrue(RefreshPolicy.shouldFetch(lastFetch: old, now: now))
    }

    // MARK: Backoff

    func testBackoffHonoursRetryAfterHeader() {
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 1, retryAfter: 42), 42)
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 5, retryAfter: 30), 30)
    }

    /// Observed in the wild: the endpoint returned `Retry-After: 1985`.
    /// Clamping that low would retry early and re-trip the limit.
    func testBackoffHonoursLongRetryAfterInFull() {
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 1, retryAfter: 1985), 1985)
    }

    func testBackoffCapsAbsurdRetryAfterAtTwoHours() {
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 1, retryAfter: 99999), 7200)
    }

    func testBackoffIgnoresNonPositiveRetryAfter() {
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 1, retryAfter: 0), 300)
    }

    func testBackoffDoublesWithoutHeader() {
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 1, retryAfter: nil), 300)
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 2, retryAfter: nil), 600)
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 3, retryAfter: nil), 1200)
    }

    func testBackoffIsCappedAtAnHour() {
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 50, retryAfter: nil), 3600)
    }
}
