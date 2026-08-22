import SwiftUI
import ClaudePetCore

struct OnboardingView: View {
    var onFinished: () -> Void

    @State private var page = 0
    private let pageCount = 3
    private let contentHeight: CGFloat = 230

    var body: some View {
        VStack(spacing: 18) {
            Group {
                switch page {
                case 0: introPage
                case 1: statesPage
                default: hotkeysPage
                }
            }
            .frame(maxWidth: .infinity, minHeight: contentHeight, maxHeight: contentHeight, alignment: .topLeading)

            HStack {
                pageDots
                Spacer()
                Button("Back") { page -= 1 }
                    .disabled(page == 0)
                    .opacity(page == 0 ? 0 : 1)
                Button(page < pageCount - 1 ? "Next" : "Set Up Hooks") {
                    if page < pageCount - 1 {
                        page += 1
                    } else {
                        onFinished()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440, height: 400)
    }

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var introPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome to ClaudePet").font(.system(size: 17, weight: .bold))
            Text("A small floating companion that reacts to what your Claude Code sessions are doing in real time - idle, working, waiting on you, ready for review, or failed - so you can tell at a glance without switching to the terminal.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statesPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What the pet is telling you").font(.system(size: 15, weight: .bold))
            ForEach(PetState.allCases, id: \.self) { state in
                HStack(spacing: 12) {
                    Text(state.emoji)
                        .font(.system(size: 20))
                        .frame(width: 28, alignment: .center)
                    Text(state.label)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }

    private var hotkeysPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Good to know").font(.system(size: 15, weight: .bold))
            hotkeyRow("⌘⇧P", "Show/hide the pet")
            hotkeyRow("⌘⇧K", "Jump to any active session by name")
            hotkeyRow("Click pet", "Open the Activity Tray")
            hotkeyRow("Right-click bubble", "Quick actions - focus, copy, end session")
            Text("One more step: wiring ClaudePet into Claude Code's hooks, so it actually hears about your sessions.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func hotkeyRow(_ key: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                .frame(width: 140, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
