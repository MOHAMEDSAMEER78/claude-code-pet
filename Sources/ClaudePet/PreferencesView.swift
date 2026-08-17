import SwiftUI

/// The single settings surface, backed by AppSettings - replaces toggles that
/// previously only existed as scattered menu-bar checkmarks with no place to
/// discover them together.
struct PreferencesView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Wander when idle", isOn: $settings.wanderEnabled)
                Toggle("Multi-Session Pets (one pet per session)", isOn: $settings.multiSessionMode)
            }
            Section("Alerts") {
                Toggle("Notify when a permission decision is needed", isOn: $settings.notificationsEnabled)
                Toggle("Play a sound on review/failure/permission", isOn: $settings.soundEnabled)
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
        .frame(width: 380, height: 300)
        .onAppear {
            // SMAppService is the source of truth - reconcile in case the
            // user removed it from System Settings > Login Items directly.
            settings.launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
