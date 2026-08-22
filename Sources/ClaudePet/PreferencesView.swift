import SwiftUI
import AppKit

/// The single settings surface, backed by AppSettings - replaces toggles that
/// previously only existed as scattered menu-bar checkmarks with no place to
/// discover them together. Split into tabs once the flat single-Form layout
/// grew past ~3 sections worth of toggles (Behavior/Startup vs. Alerts/
/// per-state notification rules) - two clearly distinct concerns, not an
/// arbitrary split.
struct PreferencesView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            GeneralPreferencesView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            AlertsPreferencesView(settings: settings)
                .tabItem { Label("Alerts", systemImage: "bell") }
            DisplayPreferencesView(settings: settings)
                .tabItem { Label("Display", systemImage: "display") }
        }
        .frame(width: 420, height: 500)
    }
}

private struct GeneralPreferencesView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Wander when idle", isOn: $settings.wanderEnabled)
                Toggle("Multi-Session Pets (one pet per session)", isOn: $settings.multiSessionMode)
                Toggle("Name pets by project (not session)", isOn: $settings.groupPetsByProject)
                Toggle("Group Activity Tray by project", isOn: $settings.groupTrayByProject)
            }
            Section("Startup") {
                Toggle("Launch ClaudePet at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        if LaunchAtLogin.setEnabled(newValue) {
                            settings.launchAtLogin = newValue
                        }
                    }
                ))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // SMAppService is the source of truth - reconcile in case the
            // user removed it from System Settings > Login Items directly.
            settings.launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

private struct DisplayPreferencesView: View {
    @ObservedObject var settings: AppSettings

    private var screens: [NSScreen] { NSScreen.screens }

    var body: some View {
        Form {
            Section("Pet Display") {
                Picker("Keep pet on", selection: Binding(
                    get: { settings.preferredScreenID },
                    set: { settings.preferredScreenID = $0 }
                )) {
                    Text("Whichever is main").tag(String?.none)
                    ForEach(screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(PetPanel.screenID(for: screen))
                    }
                }
                Picker("Corner", selection: $settings.preferredCorner) {
                    Text("Bottom Right").tag(AppSettings.ScreenCorner.bottomRight)
                    Text("Bottom Left").tag(AppSettings.ScreenCorner.bottomLeft)
                    Text("Top Right").tag(AppSettings.ScreenCorner.topRight)
                    Text("Top Left").tag(AppSettings.ScreenCorner.topLeft)
                }
            }
            Text("Takes effect the next time the pet moves to its resting spot, or immediately if the display arrangement changes.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AlertsPreferencesView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Alerts") {
                Toggle("Enable notifications", isOn: $settings.notificationsEnabled)
                Toggle("Play a sound on review/failure/permission", isOn: $settings.soundEnabled)
            }
            Section("Notify me when a session…") {
                Toggle("needs a permission decision", isOn: $settings.notifyOnPermission)
                Toggle("fails", isOn: $settings.notifyOnFailed)
                Toggle("is ready for review", isOn: $settings.notifyOnReview)
                Toggle("starts running", isOn: $settings.notifyOnRunning)
            }
            .disabled(!settings.notificationsEnabled)
            Section("Budget") {
                Toggle("Enable daily budget alerts", isOn: $settings.budgetAlertsEnabled)
                // Row is always present (dimmed/disabled when off) rather than
                // conditionally inserted, and the TextField's placeholder is
                // deliberately empty: a non-empty placeholder on this numeric
                // TextField (e.g. "10.00") reproducibly rendered as a floating
                // duplicate ABOVE the real field in this Form/Section - a
                // SwiftUI-on-macOS rendering bug, not a logic bug. The "Set an
                // amount…" caption below covers the hint a placeholder would
                // have given.
                HStack {
                    Text("Daily budget")
                    Spacer()
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("", value: $settings.dailyBudgetUSD, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }
                .disabled(!settings.budgetAlertsEnabled)
                .opacity(settings.budgetAlertsEnabled ? 1 : 0.4)
                Text(budgetCaption)
                    .font(.system(size: 10))
                    .foregroundStyle(budgetCaptionIsWarning ? .orange : .secondary)
            }
            Section("Digest") {
                Toggle("Weekly summary notification", isOn: $settings.weeklyDigestEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var budgetCaptionIsWarning: Bool {
        settings.budgetAlertsEnabled && settings.dailyBudgetUSD <= 0
    }

    private var budgetCaption: String {
        guard settings.budgetAlertsEnabled else {
            return "Turn this on to get a notification once today's est. spend crosses an amount you set."
        }
        guard settings.dailyBudgetUSD > 0 else {
            return "Set an amount above $0 - alerts stay off at $0."
        }
        return "You'll get one notification per day, the first time today's est. spend crosses this."
    }
}
