import SwiftUI
import AppKit

struct HookSetupView: View {
    @State private var checks: [HookCheck] = HookInstaller.diagnose()
    @State private var installError: String?
    @State private var justInstalled = false

    @State private var statusLineChecks: [HookCheck] = HookInstaller.diagnoseStatusLine()
    @State private var statusLineError: String?

    private var allOK: Bool { checks.allSatisfy { $0.status == .ok } }
    private var statusLineEnabled: Bool {
        FileManager.default.fileExists(atPath: HookInstaller.installedStatusLineURL.path)
    }

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

            Divider()

            Text("Claude Usage Tracking (optional)")
                .font(.system(size: 13, weight: .bold))
            Text("Shows the 5-hour/7-day rate-limit quota Claude Code itself tracks, in Session Stats. This works by claiming the statusLine setting - if you already have your own statusLine script, ClaudePet chains through to it, so your terminal's output doesn't change.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if statusLineEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(statusLineChecks) { check in
                        HStack(alignment: .top, spacing: 8) {
                            icon(for: check.status)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(check.title).font(.system(size: 11, weight: .medium))
                                Text(check.detail).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            if let statusLineError {
                Text(statusLineError).font(.system(size: 11)).foregroundStyle(.red)
            }

            HStack {
                if statusLineEnabled {
                    Button("Disable Usage Tracking") { disableStatusLine() }
                } else {
                    Button("Enable Usage Tracking") { enableStatusLine() }
                }
                Spacer()
                Button("Re-check") { statusLineChecks = HookInstaller.diagnoseStatusLine() }
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

    private func enableStatusLine() {
        statusLineError = nil
        do {
            try HookInstaller.installStatusLineWrapper()
        } catch {
            statusLineError = error.localizedDescription
        }
        statusLineChecks = HookInstaller.diagnoseStatusLine()
    }

    private func disableStatusLine() {
        statusLineError = nil
        do {
            try HookInstaller.uninstallStatusLineWrapper()
            try? FileManager.default.removeItem(at: HookInstaller.installedStatusLineURL)
        } catch {
            statusLineError = error.localizedDescription
        }
        statusLineChecks = HookInstaller.diagnoseStatusLine()
    }
}
