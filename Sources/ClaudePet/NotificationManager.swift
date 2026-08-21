import Foundation
import UserNotifications
import AppKit
import ClaudePetCore

/// Posts a native macOS notification the moment a permission request needs a
/// human decision - ClaudePet is notification-only for permissions (no
/// in-app Allow/Deny), so this always fires regardless of whether the pet
/// panel happens to be visible; it's the only signal there is. Also fires a
/// lighter-weight notification for `failed` and `review` state transitions,
/// which stays conditioned on the pet being hidden since those do have an
/// on-screen alternative (the pet's own activity card).
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var authorized = false

    func requestAuthorization() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.authorized = granted }
        }
    }

    func notifyPermissionNeeded(request: PermissionRequest) {
        guard AppSettings.shared.notificationsEnabled, AppSettings.shared.notifyOnPermission, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Claude Code needs your permission"
        content.body = request.summary ?? request.tool.map { "Wants to use \($0)" } ?? "Waiting on a decision"
        content.sound = .default
        content.categoryIdentifier = "PERMISSION_REQUEST"
        post(content, id: "permission-\(request.requestId)")
    }

    func notifyStateChange(name: String, state: PetState, appIsActive: Bool) {
        guard AppSettings.shared.notificationsEnabled, authorized, !appIsActive else { return }
        guard isEnabled(for: state) else { return }
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = body(for: state)
        content.sound = .default
        post(content, id: "state-\(name)-\(state.rawValue)-\(Int(Date().timeIntervalSince1970))")
    }

    private func isEnabled(for state: PetState) -> Bool {
        switch state {
        case .failed: return AppSettings.shared.notifyOnFailed
        case .review: return AppSettings.shared.notifyOnReview
        case .running: return AppSettings.shared.notifyOnRunning
        case .waitingPermission, .idle: return false // permission has its own dedicated path above
        }
    }

    private func body(for state: PetState) -> String {
        switch state {
        case .failed: return "Something went wrong"
        case .review: return "Done - ready for your review"
        case .running: return "Started working"
        case .waitingPermission, .idle: return state.label
        }
    }

    private func post(_ content: UNMutableNotificationContent, id: String) {
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // Show banners even while the app is running (foreground) - the default
    // is to suppress them, which would defeat the point here.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
