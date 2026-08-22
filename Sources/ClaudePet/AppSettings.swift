import Foundation
import Combine

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
        case notifyOnSessionEnd
        case groupPetsByProject
        case groupTrayByProject
        case budgetAlertsEnabled
        case dailyBudgetUSD
        case lastBudgetAlertDate
        case weeklyDigestEnabled
        case lastDigestSentAt
        case preferredScreenID
        case preferredCorner
        case showUsageInMenuBar
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
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled.rawValue) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled.rawValue) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue) }
    }
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
    @Published var notifyOnSessionEnd: Bool {
        didSet { defaults.set(notifyOnSessionEnd, forKey: Key.notifyOnSessionEnd.rawValue) }
    }
    @Published var groupPetsByProject: Bool {
        didSet { defaults.set(groupPetsByProject, forKey: Key.groupPetsByProject.rawValue) }
    }
    @Published var groupTrayByProject: Bool {
        didSet { defaults.set(groupTrayByProject, forKey: Key.groupTrayByProject.rawValue) }
    }
    @Published var budgetAlertsEnabled: Bool {
        didSet { defaults.set(budgetAlertsEnabled, forKey: Key.budgetAlertsEnabled.rawValue) }
    }
    @Published var dailyBudgetUSD: Double {
        didSet { defaults.set(dailyBudgetUSD, forKey: Key.dailyBudgetUSD.rawValue) }
    }
    @Published var lastBudgetAlertDate: Date? {
        didSet { defaults.set(lastBudgetAlertDate?.timeIntervalSince1970, forKey: Key.lastBudgetAlertDate.rawValue) }
    }
    @Published var weeklyDigestEnabled: Bool {
        didSet { defaults.set(weeklyDigestEnabled, forKey: Key.weeklyDigestEnabled.rawValue) }
    }
    @Published var lastDigestSentAt: Date? {
        didSet { defaults.set(lastDigestSentAt?.timeIntervalSince1970, forKey: Key.lastDigestSentAt.rawValue) }
    }
    @Published var preferredScreenID: String? {
        didSet { defaults.set(preferredScreenID, forKey: Key.preferredScreenID.rawValue) }
    }
    @Published var preferredCorner: ScreenCorner {
        didSet { defaults.set(preferredCorner.rawValue, forKey: Key.preferredCorner.rawValue) }
    }
    @Published var showUsageInMenuBar: Bool {
        didSet { defaults.set(showUsageInMenuBar, forKey: Key.showUsageInMenuBar.rawValue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.multiSessionMode = defaults.bool(forKey: Key.multiSessionMode.rawValue)
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
        self.notifyOnSessionEnd = defaults.object(forKey: Key.notifyOnSessionEnd.rawValue) == nil
            ? true : defaults.bool(forKey: Key.notifyOnSessionEnd.rawValue)
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
        self.showUsageInMenuBar = defaults.object(forKey: Key.showUsageInMenuBar.rawValue) == nil
            ? true : defaults.bool(forKey: Key.showUsageInMenuBar.rawValue)
    }
}
