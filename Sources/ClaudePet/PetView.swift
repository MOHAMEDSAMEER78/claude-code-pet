import SwiftUI

/// Reports the pet content's natural (unclipped) size so the hosting NSPanel
/// can resize to fit - see PetPanel.fitToContent.
private struct PetContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// The pet visuals (bubble + sprite/emoji), decoupled from where the state
/// comes from - reused by both the single aggregate pet and per-session pets.
struct PetContentView: View {
    let state: PetState
    let identityName: String
    let bubbleText: String
    let footnote: String?
    @ObservedObject var library: PetLibrary
    var overrideRow: String? = nil
    var tasksDone: Int? = nil
    var tasksTotal: Int? = nil
    var onTap: (() -> Void)?
    var pendingRequest: PermissionRequest?
    var onDecision: ((Bool) -> Void)?
    var onSizeChange: ((CGSize) -> Void)? = nil

    @State private var bobbing = false

    var body: some View {
        VStack(spacing: 6) {
            if let asset = library.current {
                PetSpriteView(asset: asset, state: state, overrideRow: overrideRow)
            } else if overrideRow == "jumping" {
                Text(state.emoji)
                    .font(.system(size: 56))
                    .offset(y: -18)
                    .shadow(radius: 3)
            } else if overrideRow == "waving" {
                Text(state.emoji)
                    .font(.system(size: 56))
                    .rotationEffect(.degrees(-12))
                    .shadow(radius: 3)
            } else {
                Text(state.emoji)
                    .font(.system(size: 56))
                    .offset(y: bobbing ? -4 : 4)
                    .animation(
                        .easeInOut(duration: animationSpeed).repeatForever(autoreverses: true),
                        value: bobbing
                    )
                    .onAppear { bobbing = true }
                    .shadow(radius: 3)
            }

            if !bubbleText.isEmpty {
                ActivityCard(
                    name: identityName,
                    message: bubbleText,
                    tasksDone: tasksDone,
                    tasksTotal: tasksTotal
                )
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if let request = pendingRequest, let onDecision {
                PermissionBubble(request: request, onDecision: onDecision)
            }
        }
        .padding(10)
        .frame(width: 190, alignment: .top)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PetContentSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PetContentSizeKey.self) { onSizeChange?($0) }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private var animationSpeed: Double {
        switch state {
        case .running: return 0.35
        case .waitingPermission: return 0.5
        case .failed: return 0.25
        default: return 1.2
        }
    }
}

/// The Codex-style "activity tray" card: pet name + a status message, with a
/// step-progress ring (e.g. "5/8") when the current turn has an active task
/// list. Replaces a plain status-text bubble with something closer to the
/// real notification card (name, message, progress badge).
struct ActivityCard: View {
    let name: String
    let message: String
    let tasksDone: Int?
    let tasksTotal: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(2)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let total = tasksTotal, total > 0, let done = tasksDone {
                TaskProgressRing(done: done, total: total)
            }
        }
        .padding(10)
        .frame(maxWidth: 180, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct TaskProgressRing: View {
    let done: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(done) / Double(total))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)")
                .font(.system(size: 8, weight: .semibold))
        }
        .frame(width: 30, height: 30)
    }
}

/// A tool-name/summary readout with Allow/Deny buttons for a blocked
/// PermissionRequest hook, shown while the pet-hook.py process is polling
/// for this exact decision.
struct PermissionBubble: View {
    let request: PermissionRequest
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(request.tool ?? "Permission needed")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            if let summary = request.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                Button("Deny") { onDecision(false) }
                    .buttonStyle(.bordered)
                    .tint(.red)
                Button("Allow") { onDecision(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: 160)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Single-pet mode: reflects the highest-priority state across all sessions.
struct PetView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var library: PetLibrary
    @ObservedObject var permissions: PermissionRequestStore
    @ObservedObject var animator: PetAnimator
    var onOpenTray: (() -> Void)? = nil
    var onSizeChange: ((CGSize) -> Void)? = nil

    var body: some View {
        let request = permissions.requestsBySession.values.min { $0.ts < $1.ts }
        PetContentView(
            state: store.aggregate,
            identityName: store.title ?? library.current?.name ?? "Claude",
            bubbleText: store.bubbleText,
            footnote: store.sessionCount > 1 ? "\(store.sessionCount) sessions - click to switch" : nil,
            library: library,
            overrideRow: animator.overrideRow,
            tasksDone: store.tasksDone,
            tasksTotal: store.tasksTotal,
            onTap: {
                animator.triggerJump()
                onOpenTray?()
            },
            pendingRequest: request,
            onDecision: { allow in
                if let request { permissions.respond(request, allow: allow) }
            },
            onSizeChange: onSizeChange
        )
    }
}

/// Multi-pet mode: one panel's content per active Claude Code session.
struct SinglePetView: View {
    @ObservedObject var viewModel: SessionPetViewModel
    @ObservedObject var library: PetLibrary
    @ObservedObject var permissions: PermissionRequestStore
    var onSizeChange: ((CGSize) -> Void)? = nil

    var body: some View {
        let request = permissions.requestsBySession[viewModel.sessionId]
        PetContentView(
            state: viewModel.state,
            identityName: viewModel.title ?? viewModel.identityName,
            bubbleText: viewModel.bubbleText,
            footnote: nil,
            library: library,
            overrideRow: viewModel.overrideRow,
            tasksDone: viewModel.tasksDone,
            tasksTotal: viewModel.tasksTotal,
            onTap: {
                viewModel.triggerJump()
                viewModel.focusTerminal()
            },
            pendingRequest: request,
            onDecision: { allow in
                if let request { permissions.respond(request, allow: allow) }
            },
            onSizeChange: onSizeChange
        )
    }
}
