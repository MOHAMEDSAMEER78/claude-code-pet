import Foundation
import Combine

/// The app's single settings model. Every persisted preference lives here as
/// a typed, observable property instead of scattered raw `UserDefaults`
/// key/get/set pairs across AppDelegate/PetAnimator/etc. - one place to look,
/// one place to add a new toggle, and a real backing store for the
/// Preferences window.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key: String {
        case multiSessionMode
        case wanderEnabled
        case soundEnabled
        case notificationsEnabled
        case launchAtLogin
    }

    private let defaults: UserDefaults

    @Published var multiSessionMode: Bool {
        didSet { defaults.set(multiSessionMode, forKey: Key.multiSessionMode.rawValue) }
    }
    @Published var wanderEnabled: Bool {
        didSet { defaults.set(wanderEnabled, forKey: Key.wanderEnabled.rawValue) }
    }
    /// Short chime on states that need attention (waiting-permission, review,
    /// failed) - off by default since not everyone wants audible alerts from
    /// a pet.
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled.rawValue) }
    }
    /// A native banner when a permission request needs a decision and the
    /// app isn't frontmost - on by default, since a missed permission bubble
    /// silently falls back to the CLI prompt with no other signal.
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled.rawValue) }
    }
    /// Mirrors SMAppService's actual registration state; LaunchAtLogin is the
    /// source of truth, this just reflects it for the Preferences UI.
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.multiSessionMode = defaults.bool(forKey: Key.multiSessionMode.rawValue)
        // wanderEnabled/notificationsEnabled default to true unless the user
        // has explicitly turned them off before.
        self.wanderEnabled = defaults.object(forKey: Key.wanderEnabled.rawValue) == nil
            ? true : defaults.bool(forKey: Key.wanderEnabled.rawValue)
        self.soundEnabled = defaults.bool(forKey: Key.soundEnabled.rawValue)
        self.notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled.rawValue) == nil
            ? true : defaults.bool(forKey: Key.notificationsEnabled.rawValue)
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin.rawValue)
    }
}
