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

    func testActiveWhenNearLimit() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: nil, maxPercent: 88, now: now),
                       RefreshPolicy.activeInterval)
    }

    func testIdleOtherwise() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: now.addingTimeInterval(-600),
                                              maxPercent: 10, now: now),
                       RefreshPolicy.idleInterval)
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: nil, maxPercent: 0, now: now),
                       RefreshPolicy.idleInterval)
    }

    func testActiveIntervalNeverBeatsTheFloor() {
        XCTAssertGreaterThanOrEqual(RefreshPolicy.activeInterval, RefreshPolicy.minimumSpacing)
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

    func testBackoffCapsAbsurdRetryAfter() {
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 1, retryAfter: 99999), 900)
    }

    func testBackoffIgnoresNonPositiveRetryAfter() {
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 1, retryAfter: 0), 60)
    }

    func testBackoffDoublesWithoutHeader() {
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 1, retryAfter: nil), 60)
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 2, retryAfter: nil), 120)
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 3, retryAfter: nil), 240)
    }

    func testBackoffIsCapped() {
        XCTAssertEqual(RefreshPolicy.backoff(consecutiveRateLimits: 50, retryAfter: nil), 600)
    }
}
