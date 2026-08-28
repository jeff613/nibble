import Foundation

public struct ModelPricing: Sendable {
    public var inputPerMTok: Double
    public var outputPerMTok: Double

    public var cacheWritePerMTok: Double { inputPerMTok * 1.25 }
    public var cacheReadPerMTok: Double { inputPerMTok * 0.1 }
}

/// Estimates what local usage would have cost at published API prices.
/// This is a "value of my subscription" figure, not a bill.
public enum Pricing {
    static let tiers: [(needle: String, pricing: ModelPricing)] = [
        ("fable", ModelPricing(inputPerMTok: 10, outputPerMTok: 50)),
        ("mythos", ModelPricing(inputPerMTok: 10, outputPerMTok: 50)),
        ("opus", ModelPricing(inputPerMTok: 5, outputPerMTok: 25)),
        ("sonnet", ModelPricing(inputPerMTok: 3, outputPerMTok: 15)),
        ("haiku", ModelPricing(inputPerMTok: 1, outputPerMTok: 5)),
        // API list price, not a bill.
        ("gpt-5.6", ModelPricing(inputPerMTok: 1.25, outputPerMTok: 10)),
        ("gpt-5", ModelPricing(inputPerMTok: 1.25, outputPerMTok: 10)),
        ("grok-4.6", ModelPricing(inputPerMTok: 3, outputPerMTok: 15)),
        ("grok-4", ModelPricing(inputPerMTok: 3, outputPerMTok: 15)),
    ]

    public static func pricing(forModel id: String) -> ModelPricing? {
        let lower = id.lowercased()
        return tiers.first { lower.contains($0.needle) }?.pricing
    }

    public static func cost(_ c: TokenCounts, model: String) -> Double? {
        guard let p = pricing(forModel: model) else { return nil }
        let m = 1_000_000.0
        return Double(c.input) / m * p.inputPerMTok
             + Double(c.output) / m * p.outputPerMTok
             + Double(c.cacheCreation) / m * p.cacheWritePerMTok
             + Double(c.cacheRead) / m * p.cacheReadPerMTok
    }

    public static func totalCost(_ totals: [DayModelKey: TokenCounts]) -> Double {
        totals.reduce(0) { sum, entry in
            sum + (cost(entry.value, model: entry.key.model) ?? 0)
        }
    }
}
