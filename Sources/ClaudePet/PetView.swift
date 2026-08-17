import SwiftUI
import ClaudePetCore

/// Colors/chrome pulled directly from a screen recording of the real Codex
/// desktop pet overlay: a solid charcoal card (not a translucent macOS
/// material), no speech-bubble tail, and a small round status badge that
/// overlaps the card's top-right corner (spinner while working, green check
/// when done).
private enum CodexChrome {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let border = Color.white.opacity(0.10)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let accent = Color(red: 0.42, green: 0.55, blue: 0.98) // Codex's default-pet blue
}

/// The real overlay's card has no tail - it just floats near the pet - and
/// a status badge that overlaps its top-right corner.
private struct CodexBubbleModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    var maxWidth: CGFloat?
    var badge: AnyView? = nil

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(CodexChrome.background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(CodexChrome.border, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if let badge {
                    badge
                        .offset(x: 6, y: -6)
                }
            }
    }
}

private extension View {
    func codexBubble(cornerRadius: CGFloat = 18, maxWidth: CGFloat? = nil, badge: AnyView? = nil) -> some View {
        modifier(CodexBubbleModifier(cornerRadius: cornerRadius, maxWidth: maxWidth, badge: badge))
    }
}

/// The small round status indicator seen overlapping the real bubble's
/// top-right corner: a spinner while a task is running, a green check once
/// it's done, matching the states the ClaudePet hook already tracks.
private struct StatusBadge: View {
    let state: PetState
    @State private var blink = false

    var body: some View {
        ZStack {
            Circle()
                .fill(CodexChrome.background)
            Circle()
                .strokeBorder(CodexChrome.border, lineWidth: 1)
            content
        }
        .frame(width: 18, height: 18)
        .onAppear {
            if state == .running { startBlinking() }
        }
        .onChange(of: state) { newState in
            if newState == .running {
                startBlinking()
            } else {
                blink = false
            }
        }
    }

    private func startBlinking() {
        blink = false
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            blink = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .running:
            Circle()
                .fill(Color.yellow)
                .frame(width: 9, height: 9)
                .opacity(blink ? 0.25 : 1)
        case .review:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        case .waitingPermission:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }
}

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
                    state: state,
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
        .frame(width: 220, alignment: .top)
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
    let state: PetState
    let name: String
    let message: String
    let tasksDone: Int?
    let tasksTotal: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CodexChrome.primaryText)
                    .lineLimit(1)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(CodexChrome.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let total = tasksTotal, total > 0, let done = tasksDone {
                TaskProgressRing(done: done, total: total)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 10))
        .codexBubble(maxWidth: 210, badge: AnyView(StatusBadge(state: state)))
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
                .stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(CodexChrome.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(CodexChrome.primaryText)
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
        VStack(spacing: 6) {
            Text(request.tool ?? "Permission needed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CodexChrome.primaryText)
                .lineLimit(1)
            if let summary = request.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 9))
                    .foregroundStyle(CodexChrome.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                CodexPillButton(title: "Deny", tint: .white.opacity(0.85), fill: .white.opacity(0.12)) {
                    onDecision(false)
                }
                CodexPillButton(title: "Allow", tint: .black, fill: CodexChrome.accent) {
                    onDecision(true)
                }
            }
        }
        .padding(10)
        .codexBubble(cornerRadius: 16, maxWidth: 190)
    }
}

/// A flat, pill-shaped button matching Codex's real button chrome (solid
/// fill, no native macOS bezel) instead of AppKit's default bordered styles.
struct CodexPillButton: View {
    let title: String
    let tint: Color
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
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
