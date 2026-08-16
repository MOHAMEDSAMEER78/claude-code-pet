import SwiftUI

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
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(session.state.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                if !cwdName.isEmpty {
                    Text(cwdName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
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
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
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
    let identityFor: (String) -> String
    let onSelect: (EffectiveSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Active Sessions")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            if store.sessions.isEmpty {
                Text("No active Claude Code sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.sessions.sorted(by: { $0.state.priority > $1.state.priority })) { session in
                            ActivityTrayRow(
                                session: session,
                                fallbackName: identityFor(session.sessionId),
                                onSelect: { onSelect(session) },
                                onKill: { store.killSession(session) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(10)
        .frame(width: 260, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
