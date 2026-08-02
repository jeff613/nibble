import XCTest
@testable import UsageBarCore

final class RefreshPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func testActiveWhenRecentActivity() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: now.addingTimeInterval(-60),
                                              maxPercent: 10, now: now), 10)
    }

    func testActiveWhenNearLimit() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: nil, maxPercent: 88, now: now), 10)
    }

    func testIdleOtherwise() {
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: now.addingTimeInterval(-600),
                                              maxPercent: 10, now: now), 60)
        XCTAssertEqual(RefreshPolicy.interval(lastActivity: nil, maxPercent: 0, now: now), 60)
    }
}
