import SwiftUI
import ClaudePetCore

/// The pet's permission-decision UI, revamped to be genuinely hard to miss
/// where it already lives - inside the pet's own card, not a second floating
/// window elsewhere on screen, which would just split attention between two
/// places for the same decision. Bigger, higher-contrast, and now shows a
/// live countdown to pet-hook.py's own await-permission timeout, so "how
/// long do I actually have before this silently falls back to the terminal
/// prompt" is visible instead of a mystery. A pulsing amber/red glow that
/// intensifies as time runs low does the "hard to miss" work that a
/// separate overlay window would otherwise be for.
struct PermissionOverlayCard: View {
    let request: PermissionRequest
    let onDecision: (Bool) -> Void

    /// Mirrors pet-hook.py's AWAIT_PERMISSION_TIMEOUT_SECONDS. The two live
    /// in different processes/languages so this can drift out of sync with
    /// the real value; harmless if it does; the countdown is a UX aid, not
    /// what actually enforces the timeout.
    private static let timeoutSeconds: TimeInterval = 45

    @State private var pulse = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Self.timeoutSeconds - (context.date.timeIntervalSince1970 - request.ts))
            card(remaining: remaining)
        }
    }

    private func urgencyColor(_ remaining: TimeInterval) -> Color {
        if remaining <= 10 { return Color(red: 0.94, green: 0.36, blue: 0.32) }
        if remaining <= 20 { return Color(red: 0.96, green: 0.68, blue: 0.29) }
        return Color(red: 0.42, green: 0.55, blue: 0.98)
    }

    @ViewBuilder
    private func card(remaining: TimeInterval) -> some View {
        let color = urgencyColor(remaining)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text("Needs your permission")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(remaining))s")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .contentTransition(.numericText(countsDown: true))
            }

            ProgressView(value: remaining, total: Self.timeoutSeconds)
                .tint(color)
                .scaleEffect(x: 1, y: 0.7, anchor: .center)

            VStack(alignment: .leading, spacing: 4) {
                if let tool = request.tool {
                    Text(tool)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                if let summary = request.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                CodexPillButton(
                    title: "Deny", tint: .white.opacity(0.85), fill: .white.opacity(0.12),
                    fontSize: 12, expand: true
                ) { onDecision(false) }
                CodexPillButton(
                    title: "Allow", tint: .black, fill: color,
                    fontSize: 12, expand: true
                ) { onDecision(true) }
            }
        }
        .padding(14)
        .frame(maxWidth: 210, alignment: .leading)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(color.opacity(pulse ? 0.9 : 0.35), lineWidth: 2)
        )
        .shadow(color: color.opacity(pulse ? 0.55 : 0.18), radius: pulse ? 14 : 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
