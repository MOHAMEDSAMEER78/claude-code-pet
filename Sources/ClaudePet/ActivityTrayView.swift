import SwiftUI
import ClaudePetCore

/// One row in the Activity Tray: a session's chat summary, status, and
/// current activity, selectable to jump to that session's terminal -
/// mirroring the real Codex tray ("select an activity to open its chat").
struct ActivityTrayRow: View {
    let session: EffectiveSession
    /// Fallback name only for the brief window before a session's first
    /// prompt has been captured (no chat summary exists yet).
    let fallbackName: String
    let onSelect: () -> Void
    let onKill: () -> Void

    @State private var confirmingKill = false
    @State private var usage: TranscriptUsage.Totals?

    private var displayTitle: String {
        session.title ?? fallbackName
    }

    private var cwdName: String {
        session.bubbleText // "cwd · tool · summary" style text
    }

    private var dotColor: Color {
        switch session.state {
        case .waitingPermission: return .orange
        case .failed: return .red
        case .review: return .green
        case .running: return .blue
        case .idle: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(displayTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(session.state.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                            .fixedSize()
                    }
                    if !cwdName.isEmpty {
                        Text(cwdName)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    if let usage {
                        Text("\(Self.formatTokens(usage.totalTokens)) tok · \(Self.formatCost(usage.estimatedCostUSD)) est.\(usage.isRoughEstimate ? " (unrecognized model)" : "")")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
                Spacer(minLength: 4)
                if let total = session.tasksTotal, total > 0, let done = session.tasksDone {
                    TaskProgressRing(done: done, total: total)
                        .frame(width: 22, height: 22)
                }
                killButton
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .task(id: session.sessionId) {
            // Off the main actor's synchronous path deliberately - reading a
            // transcript is a file read that can occasionally be a few MB,
            // and this must never stall the tray from opening.
            let sessionId = session.sessionId
            let result = await Task.detached(priority: .utility) {
                TranscriptUsage.totals(forSession: sessionId)
            }.value
            usage = result
        }
    }

    private static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        return "\(count)"
    }

    private static func formatCost(_ usd: Double) -> String {
        usd < 0.01 && usd > 0 ? "<$0.01" : String(format: "$%.2f", usd)
    }

    /// Tap once to arm ("Sure?"), tap again within 3s to confirm - avoids a
    /// blocking system alert in a non-activating panel while still
    /// preventing an accidental single-click kill.
    @ViewBuilder
    private var killButton: some View {
        Button(action: handleKillTap) {
            Image(systemName: confirmingKill ? "questionmark.circle.fill" : "xmark.circle")
                .foregroundStyle(confirmingKill ? .red : .secondary)
        }
        .buttonStyle(.plain)
        .help(confirmingKill ? "Click again to end this session" : "End this Claude Code session")
    }

    private func handleKillTap() {
        if confirmingKill {
            confirmingKill = false
            onKill()
        } else {
            confirmingKill = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                confirmingKill = false
            }
        }
    }
}

/// The full tray: every active Claude Code session, highest-priority first
/// (needs-input > blocked > ready > running > idle - same ordering as the
/// single-pet aggregate), opened by clicking the pet.
struct ActivityTrayView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: AppSettings = .shared
    let identityFor: (String) -> String
    let onSelect: (EffectiveSession) -> Void

    @State private var searchText: String = ""
    @State private var filter: TrayFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Active Sessions")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 4)

            if !store.sessions.isEmpty {
                controls
            }

            if store.sessions.isEmpty {
                Text("No active Claude Code sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(8)
            } else {
                ScrollView {
                    if settings.groupTrayByProject {
                        groupedList
                    } else {
                        flatList
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(10)
        .frame(width: 260, alignment: .top)
        .background(Color(red: 0.09, green: 0.09, blue: 0.10), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var controls: some View {
        VStack(spacing: 6) {
            TextField("Search sessions…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            Picker("", selection: $filter) {
                ForEach(TrayFilter.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 4)
    }

    private var flatList: some View {
        VStack(spacing: 4) {
            ForEach(TrayLogic.visibleSessions(store.sessions, searchText: searchText, filter: filter)) { session in
                row(for: session)
            }
        }
    }

    private var groupedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(TrayLogic.groupedByProject(store.sessions, searchText: searchText, filter: filter), id: \.key) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.key)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 4)
                    ForEach(group.sessions) { session in
                        row(for: session)
                    }
                }
            }
        }
    }

    private func row(for session: EffectiveSession) -> some View {
        ActivityTrayRow(
            session: session,
            fallbackName: identityFor(session.sessionId),
            onSelect: { onSelect(session) },
            onKill: { store.killSession(session) }
        )
    }
}
