import SwiftUI
import AppKit

/// First-run setup + anytime diagnostics for the hook↔app bridge. Replaces
/// "paste this Python snippet-merge script into your terminal" with a single
/// button, and doubles as the self-serve fix for "the pet just isn't
/// reacting" - the most likely support request for a tool with no
/// first-party API to fall back on.
struct HookSetupView: View {
    @State private var checks: [HookCheck] = HookInstaller.diagnose()
    @State private var installError: String?
    @State private var justInstalled = false

    private var allOK: Bool { checks.allSatisfy { $0.status == .ok } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hook Setup & Diagnostics")
                .font(.system(size: 15, weight: .bold))

            Text("ClaudePet reacts to Claude Code by way of hooks wired into ~/.claude/settings.json. This checks that wiring and can fix it automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(checks) { check in
                    HStack(alignment: .top, spacing: 8) {
                        icon(for: check.status)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(check.title).font(.system(size: 12, weight: .medium))
                            Text(check.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            if let installError {
                Text(installError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            if justInstalled {
                Text("Hooks installed. Restart any running Claude Code sessions to pick them up.")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }

            HStack {
                Button("Re-check") { checks = HookInstaller.diagnose() }
                Button(allOK ? "Repair Hooks" : "Install Hooks Automatically") { install() }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Reveal settings.json") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
                    ])
                }
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    @ViewBuilder
    private func icon(for status: HookCheck.Status) -> some View {
        switch status {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .missing: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func install() {
        installError = nil
        justInstalled = false
        do {
            try HookInstaller.install()
            justInstalled = true
        } catch {
            installError = error.localizedDescription
        }
        checks = HookInstaller.diagnose()
    }
}
