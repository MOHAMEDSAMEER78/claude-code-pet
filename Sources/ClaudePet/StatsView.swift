import SwiftUI

/// A local-only activity summary drawn from SessionHistoryStore. Deliberately
/// doesn't show "time worked" - the hook payloads give us a last-write
/// timestamp per session, not a trustworthy session-start time, so showing a
/// duration would mean making numbers up.
struct StatsView: View {
    let stats: SessionHistoryStore.Stats
    /// Currently-active session ids, so we can show a live "what am I
    /// spending right now" figure alongside the historical counters -
    /// summed from Claude Code's own transcript files, not the history log.
    var activeSessionIds: [String] = []

    @State private var activeSpendUSD: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Stats")
                .font(.system(size: 15, weight: .bold))
            Text("Local only - never leaves this Mac.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                stat("Sessions today", "\(stats.sessionsToday)")
                stat("Sessions this week", "\(stats.sessionsThisWeek)")
                stat("Tasks completed (7d)", "\(stats.tasksCompletedThisWeek)")
            }

            if !activeSessionIds.isEmpty {
                stat("Active sessions, est. spend", activeSpendUSD.map { String(format: "$%.2f", $0) } ?? "…")
                Text("Estimated from Claude Code's own transcripts (undocumented format) using rough per-model pricing - a ballpark, not a bill.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 340)
        .task(id: activeSessionIds) {
            let ids = activeSessionIds
            let total = await Task.detached(priority: .utility) {
                ids.reduce(0.0) { $0 + (TranscriptUsage.totals(forSession: $1)?.estimatedCostUSD ?? 0) }
            }.value
            activeSpendUSD = total
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
