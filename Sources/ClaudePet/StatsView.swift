import SwiftUI
import Charts
import ClaudePetCore

struct StatsView: View {
    let stats: SessionHistoryStore.Stats
    var activeSessionIds: [String] = []
    var decodeWarning: String?
    var progress: PetProgress? = nil
    var dailyBuckets: [DailyBucket] = []
    var projectTotals: [ProjectTotal] = []
    var usage: UsageSnapshot? = nil

    @State private var activeSpendUSD: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Session Stats")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                if let progress { moodBadge(progress) }
            }
            Text("Local only - never leaves this Mac.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                stat("Sessions today", "\(stats.sessionsToday)")
                stat("Sessions this week", "\(stats.sessionsThisWeek)")
                stat("Tasks completed (7d)", "\(stats.tasksCompletedThisWeek)")
                stat("Time worked today", Self.formatDuration(stats.secondsWorkedToday))
                stat("Time worked (7d)", Self.formatDuration(stats.secondsWorkedThisWeek))
            }

            if !activeSessionIds.isEmpty {
                stat("Active sessions, est. spend", activeSpendUSD.map { String(format: "$%.2f", $0) } ?? "…")
                Text("Estimated from Claude Code's own transcripts (undocumented format) using rough per-model pricing - a ballpark, not a bill.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if let usage { claudeQuota(usage) }

            if !dailyBuckets.isEmpty { trendChart }
            if !projectTotals.isEmpty { projectBreakdown }

            if let decodeWarning {
                Text("⚠️ \(decodeWarning)")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
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

    private func moodBadge(_ progress: PetProgress) -> some View {
        HStack(spacing: 6) {
            if progress.streakDays > 0 {
                Label("\(progress.streakDays)d", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
            }
            Label("Lv \(progress.level)", systemImage: "star.fill")
                .foregroundStyle(.yellow)
        }
        .font(.system(size: 11, weight: .semibold))
        .help("\(progress.totalSessions) sessions and \(progress.totalTasksCompleted) tasks completed all-time (\(progress.xp) xp)")
    }

    private func claudeQuota(_ usage: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude usage")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                quotaTile("5h quota", usedPct: usage.fiveHourUsedPct)
                quotaTile("7d quota", usedPct: usage.sevenDayUsedPct)
            }
            if let updatedAt = usage.updatedAt {
                let age = Date().timeIntervalSince1970 - updatedAt
                Text(age < 3600
                    ? "Updated \(max(1, Int(age / 60)))m ago"
                    : "Updated over an hour ago - stale until your next Claude Code turn")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func quotaTile(_ label: String, usedPct: Double?) -> some View {
        let used = usedPct ?? 0
        let remaining = max(0, 100 - used)
        let color: Color = used >= 80 ? .red : (used >= 50 ? .orange : .green)
        return VStack(alignment: .leading, spacing: 2) {
            Text(usedPct == nil ? "—" : "\(Int(remaining))% left")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(usedPct == nil ? .secondary : color)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(usedPct == nil ? "\(label): no data" : "\(label): \(Int(remaining)) percent left")
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Spend, last \(dailyBuckets.count) days")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Chart(dailyBuckets, id: \.date) { bucket in
                BarMark(
                    x: .value("Day", bucket.date, unit: .day),
                    y: .value("Cost", bucket.costUSD)
                )
            }
            .frame(height: 90)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, dailyBuckets.count / 5)))
            }
        }
    }

    private var projectBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By project (all time)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(projectTotals.prefix(5), id: \.project) { total in
                HStack {
                    Text(total.project).font(.system(size: 11)).lineLimit(1)
                    Spacer()
                    Text(String(format: "$%.2f", total.costUSD))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
