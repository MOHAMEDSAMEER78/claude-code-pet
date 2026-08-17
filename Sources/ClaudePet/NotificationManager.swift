import Foundation
import UserNotifications
import AppKit
import ClaudePetCore

/// Posts a native macOS notification the moment a permission request needs a
/// human decision and the app isn't frontmost to see the in-bubble Allow/Deny
/// prompt. Closes the biggest reliability gap in the pet-bubble design: today
/// a hidden/off-screen pet lets a PermissionRequest silently time out after
/// 45s and fall back to the CLI prompt with zero other signal. Also fires a
/// lighter-weight notification for `failed` and `review` state transitions,
/// since those are also easy to miss with the pet tucked away.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var authorized = false

    func requestAuthorization() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.authorized = granted }
        }
    }

    func notifyPermissionNeeded(request: PermissionRequest, appIsActive: Bool) {
        guard AppSettings.shared.notificationsEnabled, authorized, !appIsActive else { return }
        let content = UNMutableNotificationContent()
        content.title = "Claude Code needs your permission"
        content.body = request.summary ?? request.tool.map { "Wants to use \($0)" } ?? "Waiting on a decision"
        content.sound = .default
        content.categoryIdentifier = "PERMISSION_REQUEST"
        post(content, id: "permission-\(request.requestId)")
    }

    func notifyStateChange(name: String, state: PetState, appIsActive: Bool) {
        guard AppSettings.shared.notificationsEnabled, authorized, !appIsActive else { return }
        guard state == .failed || state == .review else { return }
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = state == .failed ? "Something went wrong" : "Done - ready for your review"
        content.sound = .default
        post(content, id: "state-\(name)-\(state.rawValue)-\(Int(Date().timeIntervalSince1970))")
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
