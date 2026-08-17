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
    /// Non-nil only when this session has a pending permission decision -
    /// lets Allow/Deny happen right from the tray row instead of requiring
    /// the single floating bubble (which only ever surfaces one session's
    /// request at a time) to be showing this exact session.
    var pendingRequest: PermissionRequest? = nil
    var onDecision: ((Bool) -> Void)? = nil

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

            if let request = pendingRequest, let onDecision {
                permissionRow(request: request, onDecision: onDecision)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Inline Allow/Deny for this session's pending permission request - the
    /// tray can list several sessions at once, but the single floating pet
    /// bubble only ever shows the oldest one, so any other session needing a
    /// decision would otherwise be stuck with no way to answer it from the
    /// overlay.
    @ViewBuilder
    private func permissionRow(request: PermissionRequest, onDecision: @escaping (Bool) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let summary = request.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                CodexPillButton(title: "Deny", tint: .white.opacity(0.85), fill: .white.opacity(0.12)) {
                    onDecision(false)
                }
                CodexPillButton(title: "Allow", tint: .black, fill: Color(red: 0.42, green: 0.55, blue: 0.98)) {
                    onDecision(true)
                }
            }
        }
        .padding(.leading, 16)
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
    @ObservedObject var permissions: PermissionRequestStore
    let identityFor: (String) -> String
    let onSelect: (EffectiveSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Active Sessions")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 4)

            if store.sessions.isEmpty {
                Text("No active Claude Code sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.sessions.sorted(by: { $0.state.priority > $1.state.priority })) { session in
                            ActivityTrayRow(
                                session: session,
                                fallbackName: identityFor(session.sessionId),
                                onSelect: { onSelect(session) },
                                onKill: { store.killSession(session) },
                                pendingRequest: permissions.requestsBySession[session.sessionId],
                                onDecision: { allow in
                                    if let request = permissions.requestsBySession[session.sessionId] {
                                        permissions.respond(request, allow: allow)
                                    }
                                }
                            )
                        }
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
}
