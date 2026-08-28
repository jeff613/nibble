import XCTest
@testable import NibbleCore

final class PricingTests: XCTestCase {
    func testTierMatching() {
        XCTAssertEqual(Pricing.pricing(forModel: "claude-fable-5")?.inputPerMTok, 10)
        XCTAssertEqual(Pricing.pricing(forModel: "claude-opus-5")?.outputPerMTok, 25)
        XCTAssertEqual(Pricing.pricing(forModel: "claude-sonnet-5")?.inputPerMTok, 3)
        XCTAssertEqual(Pricing.pricing(forModel: "claude-haiku-4-5-20251001")?.outputPerMTok, 5)
        XCTAssertEqual(Pricing.pricing(forModel: "gpt-5.6-sol")?.inputPerMTok, 1.25)
        XCTAssertEqual(Pricing.pricing(forModel: "grok-4.6-build")?.inputPerMTok, 3)
    }

    func testTotalCostIncludesGrok() {
        var c = TokenCounts()
        c.output = 1_000_000
        let totals = [
            DayModelKey(day: "2026-08-01", model: "grok-4.6"): c,
            DayModelKey(day: "2026-08-01", model: "mystery"): c,
        ]
        XCTAssertEqual(Pricing.totalCost(totals), 15.0, accuracy: 0.01)
    }

    func testCacheRatesDeriveFromInput() {
        let p = Pricing.pricing(forModel: "claude-fable-5")!
        XCTAssertEqual(p.cacheWritePerMTok, 12.5, accuracy: 0.001)
        XCTAssertEqual(p.cacheReadPerMTok, 1.0, accuracy: 0.001)
    }

    func testCostMath() {
        var c = TokenCounts()
        c.input = 1_000_000
        c.output = 100_000
        c.cacheCreation = 2_000_000
        c.cacheRead = 10_000_000
        // fable: 1M×$10 + 0.1M×$50 + 2M×$12.50 + 10M×$1 = 10 + 5 + 25 + 10 = 50
        XCTAssertEqual(Pricing.cost(c, model: "claude-fable-5")!, 50.0, accuracy: 0.01)
        XCTAssertNil(Pricing.cost(c, model: "unknown-model"))
    }

    func testTotalCostSkipsUnknownModels() {
        var c = TokenCounts()
        c.output = 1_000_000
        let totals = [
            DayModelKey(day: "2026-08-01", model: "claude-fable-5"): c,
            DayModelKey(day: "2026-08-01", model: "mystery"): c,
        ]
        XCTAssertEqual(Pricing.totalCost(totals), 50.0, accuracy: 0.01)
    }
}
