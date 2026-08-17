import SwiftUI

/// A local-only activity summary drawn from SessionHistoryStore. Deliberately
/// doesn't show "time worked" - the hook payloads give us a last-write
/// timestamp per session, not a trustworthy session-start time, so showing a
/// duration would mean making numbers up.
struct StatsView: View {
    let stats: SessionHistoryStore.Stats

    private var approvalRate: String {
        let total = stats.permissionsApproved + stats.permissionsDenied
        guard total > 0 else { return "—" }
        return "\(Int(100 * Double(stats.permissionsApproved) / Double(total)))%"
    }

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
                stat("Permission approval rate", approvalRate)
            }
        }
        .padding(18)
        .frame(width: 340)
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
