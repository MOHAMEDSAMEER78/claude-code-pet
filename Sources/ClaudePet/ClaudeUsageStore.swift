import Foundation

struct UsageSnapshot: Codable {
    var fiveHourUsedPct: Double?
    var sevenDayUsedPct: Double?
    var costUSD: Double?
    var contextUsedPct: Double?
    var updatedAt: TimeInterval?
}

enum ClaudeUsageStore {
    private static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/pet/usage.json")

    static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
