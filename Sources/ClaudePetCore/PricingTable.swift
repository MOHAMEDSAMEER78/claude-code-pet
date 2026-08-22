import Foundation

public enum PricingTable {
    public struct Rates: Equatable {
        public var input: Double
        public var output: Double
        public var cacheWrite: Double
        public var cacheRead: Double

        public init(input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
            self.input = input
            self.output = output
            self.cacheWrite = cacheWrite
            self.cacheRead = cacheRead
        }
    }

    public static let lastUpdated = "2026-08-21"

    public static func rates(for model: String?) -> Rates {
        let m = (model ?? "").lowercased()
        if m.contains("opus") { return Rates(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5) }
        if m.contains("haiku") { return Rates(input: 0.8, output: 4, cacheWrite: 1, cacheRead: 0.08) }
        return Rates(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3)
    }

    public static func isKnownModel(_ model: String?) -> Bool {
        let m = (model ?? "").lowercased()
        return m.contains("opus") || m.contains("haiku") || m.contains("sonnet")
    }

    public static func estimatedCostUSD(model: String?, input: Int, output: Int, cacheCreate: Int, cacheRead: Int) -> Double {
        let rates = rates(for: model)
        let million = 1_000_000.0
        return Double(input) * rates.input / million
            + Double(output) * rates.output / million
            + Double(cacheCreate) * rates.cacheWrite / million
            + Double(cacheRead) * rates.cacheRead / million
    }
}
