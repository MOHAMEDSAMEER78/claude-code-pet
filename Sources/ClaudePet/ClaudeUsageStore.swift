import Foundation

/// Snapshot of Claude Code's own rate-limit/cost/context usage, captured by
/// the optional pet-statusline.py wrapper (see HookInstaller
/// .installStatusLineWrapper) into ~/.claude/pet/usage.json each time
/// Claude Code renders its status line. `nil` fields mean that particular
/// piece wasn't present in the payload (e.g. an older Claude Code version).
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

    /// `nil` if usage tracking was never enabled (no file yet) or the file
    /// is unreadable - callers should treat that as "no data" rather than
    /// an error, since this feature is opt-in.
    static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
