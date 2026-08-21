import Foundation
import Testing
@testable import ClaudePetCore

struct PricingTests {
    // MARK: - rates

    @Test func opusRatesMatchKnownTier() {
        #expect(PricingTable.rates(for: "claude-opus-4") == PricingTable.Rates(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5))
    }

    @Test func haikuRatesMatchKnownTier() {
        #expect(PricingTable.rates(for: "claude-haiku-4.5") == PricingTable.Rates(input: 0.8, output: 4, cacheWrite: 1, cacheRead: 0.08))
    }

    @Test func sonnetRatesMatchKnownTier() {
        #expect(PricingTable.rates(for: "claude-sonnet-5") == PricingTable.Rates(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3))
    }

    @Test func unknownModelFallsBackToSonnetRates() {
        #expect(PricingTable.rates(for: "some-future-model") == PricingTable.rates(for: "sonnet"))
    }

    @Test func nilModelFallsBackToSonnetRates() {
        #expect(PricingTable.rates(for: nil) == PricingTable.rates(for: "sonnet"))
    }

    // MARK: - isKnownModel

    @Test func knownModelNamesAreRecognized() {
        #expect(PricingTable.isKnownModel("claude-opus-4"))
        #expect(PricingTable.isKnownModel("claude-haiku-4.5"))
        #expect(PricingTable.isKnownModel("claude-sonnet-5"))
    }

    @Test func unrecognizedModelNamesAreNotKnown() {
        #expect(!PricingTable.isKnownModel("some-future-model"))
        #expect(!PricingTable.isKnownModel(nil))
    }

    // MARK: - estimatedCostUSD

    @Test func costIsZeroForZeroTokens() {
        #expect(PricingTable.estimatedCostUSD(model: "sonnet", input: 0, output: 0, cacheCreate: 0, cacheRead: 0) == 0)
    }

    @Test func costScalesWithTokenCounts() {
        let cost = PricingTable.estimatedCostUSD(model: "sonnet", input: 1_000_000, output: 0, cacheCreate: 0, cacheRead: 0)
        #expect(cost == 3)
    }
}
