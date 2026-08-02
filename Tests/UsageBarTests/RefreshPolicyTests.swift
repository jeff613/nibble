import XCTest
@testable import UsageBarCore

final class RefreshPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Poll interval

    func testActiveWhenRecentActivity() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: now.addingTimeInterval(-60),
                                              maxPercent: 10, now: now),
                       RefreshPolicy.activeInterval)
    }

    func testNearLimitPollsFastestEvenWhenIdle() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: nil, maxPercent: 88, now: now),
                       RefreshPolicy.nearLimitInterval)
    }

    func testIdleOtherwise() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: now.addingTimeInterval(-600),
                                              maxPercent: 10, now: now),
                       RefreshPolicy.idleInterval)
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: nil, maxPercent: 0, now: now),
                       RefreshPolicy.idleInterval)
    }

    func testNoIntervalBeatsTheFloor() {
        for interval in [RefreshPolicy.nearLimitInterval,
                         RefreshPolicy.activeInterval,
                         RefreshPolicy.idleInterval] {
            XCTAssertGreaterThanOrEqual(interval, RefreshPolicy.minimumSpacing)
        }
    }

    func testWorstCaseStaysUnderSixtyRequestsPerHour() {
        let fastest = min(RefreshPolicy.nearLimitInterval, RefreshPolicy.minimumSpacing)
        XCTAssertLessThanOrEqual(3600 / fastest, 60)
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
