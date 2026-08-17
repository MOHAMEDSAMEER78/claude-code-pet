import Foundation
import ServiceManagement

/// Thin wrapper around SMAppService for the main app's login-item
/// registration - README previously listed this as "planned"; SMAppService
/// (macOS 13+, already the app's minimum target) needs no separate helper
/// bundle or privileged XPC service for a plain, non-sandboxed app like this.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("ClaudePet: failed to \(enabled ? "register" : "unregister") login item: \(error)")
            return false
        }
    }
}
