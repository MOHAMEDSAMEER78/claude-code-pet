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
        case notifyOnFailed
        case notifyOnReview
        case notifyOnPermission
        case notifyOnRunning
        case groupPetsByProject
        case groupTrayByProject
        case budgetAlertsEnabled
        case dailyBudgetUSD
        case lastBudgetAlertDate
        case weeklyDigestEnabled
        case lastDigestSentAt
        case preferredScreenID
        case preferredCorner
    }

    enum ScreenCorner: String, CaseIterable {
        case bottomLeft, bottomRight, topLeft, topRight
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
    /// Per-state notification rules, replacing NotificationManager's
    /// previously-hardcoded "only failed/review, always permission" gating.
    /// Defaults preserve exactly that prior behavior so existing users see
    /// no change unless they open Preferences.
    @Published var notifyOnFailed: Bool {
        didSet { defaults.set(notifyOnFailed, forKey: Key.notifyOnFailed.rawValue) }
    }
    @Published var notifyOnReview: Bool {
        didSet { defaults.set(notifyOnReview, forKey: Key.notifyOnReview.rawValue) }
    }
    @Published var notifyOnPermission: Bool {
        didSet { defaults.set(notifyOnPermission, forKey: Key.notifyOnPermission.rawValue) }
    }
    @Published var notifyOnRunning: Bool {
        didSet { defaults.set(notifyOnRunning, forKey: Key.notifyOnRunning.rawValue) }
    }
    /// In Multi-Session Pets mode, key each pet's display name off its
    /// project directory instead of its session id, so every session in the
    /// same repo consistently shows the same named pet across relaunches.
    @Published var groupPetsByProject: Bool {
        didSet { defaults.set(groupPetsByProject, forKey: Key.groupPetsByProject.rawValue) }
    }
    /// Groups the Activity Tray's session list by project (cwd basename)
    /// instead of one flat priority-sorted list.
    @Published var groupTrayByProject: Bool {
        didSet { defaults.set(groupTrayByProject, forKey: Key.groupTrayByProject.rawValue) }
    }
    /// Off by default - a budget only makes sense once the user sets one.
    @Published var budgetAlertsEnabled: Bool {
        didSet { defaults.set(budgetAlertsEnabled, forKey: Key.budgetAlertsEnabled.rawValue) }
    }
    /// `nil`/0 means "not set yet" - the alert check treats either as "no budget".
    @Published var dailyBudgetUSD: Double {
        didSet { defaults.set(dailyBudgetUSD, forKey: Key.dailyBudgetUSD.rawValue) }
    }
    /// Date (not just day) of the last time the budget alert fired, so it
    /// only fires once per calendar day even while checks keep running.
    @Published var lastBudgetAlertDate: Date? {
        didSet { defaults.set(lastBudgetAlertDate?.timeIntervalSince1970, forKey: Key.lastBudgetAlertDate.rawValue) }
    }
    @Published var weeklyDigestEnabled: Bool {
        didSet { defaults.set(weeklyDigestEnabled, forKey: Key.weeklyDigestEnabled.rawValue) }
    }
    @Published var lastDigestSentAt: Date? {
        didSet { defaults.set(lastDigestSentAt?.timeIntervalSince1970, forKey: Key.lastDigestSentAt.rawValue) }
    }
    /// `NSScreenNumber` (from a screen's deviceDescription) of the display
    /// the pet should stay docked to; nil/disconnected falls back to
    /// `NSScreen.main`.
    @Published var preferredScreenID: String? {
        didSet { defaults.set(preferredScreenID, forKey: Key.preferredScreenID.rawValue) }
    }
    @Published var preferredCorner: ScreenCorner {
        didSet { defaults.set(preferredCorner.rawValue, forKey: Key.preferredCorner.rawValue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.multiSessionMode = defaults.bool(forKey: Key.multiSessionMode.rawValue)
        // wanderEnabled/notificationsEnabled/notifyOnFailed/notifyOnReview/
        // notifyOnPermission default to true unless explicitly turned off.
        self.wanderEnabled = defaults.object(forKey: Key.wanderEnabled.rawValue) == nil
            ? true : defaults.bool(forKey: Key.wanderEnabled.rawValue)
        self.soundEnabled = defaults.bool(forKey: Key.soundEnabled.rawValue)
        self.notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled.rawValue) == nil
            ? true : defaults.bool(forKey: Key.notificationsEnabled.rawValue)
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin.rawValue)
        self.notifyOnFailed = defaults.object(forKey: Key.notifyOnFailed.rawValue) == nil
            ? true : defaults.bool(forKey: Key.notifyOnFailed.rawValue)
        self.notifyOnReview = defaults.object(forKey: Key.notifyOnReview.rawValue) == nil
            ? true : defaults.bool(forKey: Key.notifyOnReview.rawValue)
        self.notifyOnPermission = defaults.object(forKey: Key.notifyOnPermission.rawValue) == nil
            ? true : defaults.bool(forKey: Key.notifyOnPermission.rawValue)
        self.notifyOnRunning = defaults.bool(forKey: Key.notifyOnRunning.rawValue)
        self.groupPetsByProject = defaults.bool(forKey: Key.groupPetsByProject.rawValue)
        self.groupTrayByProject = defaults.bool(forKey: Key.groupTrayByProject.rawValue)
        self.budgetAlertsEnabled = defaults.bool(forKey: Key.budgetAlertsEnabled.rawValue)
        self.dailyBudgetUSD = defaults.object(forKey: Key.dailyBudgetUSD.rawValue) == nil
            ? 0 : defaults.double(forKey: Key.dailyBudgetUSD.rawValue)
        self.lastBudgetAlertDate = (defaults.object(forKey: Key.lastBudgetAlertDate.rawValue) as? TimeInterval)
            .map { Date(timeIntervalSince1970: $0) }
        self.weeklyDigestEnabled = defaults.bool(forKey: Key.weeklyDigestEnabled.rawValue)
        self.lastDigestSentAt = (defaults.object(forKey: Key.lastDigestSentAt.rawValue) as? TimeInterval)
            .map { Date(timeIntervalSince1970: $0) }
        self.preferredScreenID = defaults.string(forKey: Key.preferredScreenID.rawValue)
        self.preferredCorner = defaults.string(forKey: Key.preferredCorner.rawValue)
            .flatMap(ScreenCorner.init(rawValue:)) ?? .bottomRight
    }
}
