import SwiftUI

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
        }
        .frame(width: 380, height: 360)
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
        }
        .formStyle(.grouped)
    }
}
