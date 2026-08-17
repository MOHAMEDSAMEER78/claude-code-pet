import Foundation
import Combine
import ClaudePetCore

/// Watches ~/.claude/pet/requests/*.json for pending permission requests -
/// purely to know when to fire a native notification (see
/// AppDelegate.wireAlerts). ClaudePet is notification-only for permissions:
/// most tool calls are already auto-approved, an actual PermissionRequest is
/// rare, and there's no in-app Allow/Deny - pet-hook.py's await-permission
/// returns immediately and lets Claude Code's own terminal prompt handle the
/// decision.
final class PermissionRequestStore: ObservableObject {
    @Published private(set) var requestsBySession: [String: PermissionRequest] = [:]

    private let requestsDir: URL
    private var dirWatcher: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    /// Push path: pet-hook.py pings this the instant it writes a request
    /// file, so the notification usually fires immediately rather than
    /// waiting on FSEvent or the poll-timer fallback below.
    private let notifier = IPCNotifier(socketName: "notify-requests.sock")

    /// Requests older than this are dropped - pet-hook.py no longer removes
    /// its own request file (nothing waits on a response to clean up after
    /// anymore), so this is what actually clears them, not just a backstop.
    private static let staleSeconds: TimeInterval = 60

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        requestsDir = home.appendingPathComponent(".claude/pet/requests", isDirectory: true)
        try? FileManager.default.createDirectory(at: requestsDir, withIntermediateDirectories: true)
        startWatching()
        refresh()
    }

    private func startWatching() {
        let fd = open(requestsDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in self?.refresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        dirWatcher = source

        notifier.start { [weak self] in self?.refresh() }

        // Last-resort fallback (missed socket ping + missed FSEvent) and
        // what actually drives clearing an expired request by wall-clock
        // time alone.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let now = Date().timeIntervalSince1970
        let files = (try? FileManager.default.contentsOfDirectory(
            at: requestsDir, includingPropertiesForKeys: nil)) ?? []

        var bySession: [String: PermissionRequest] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let request = try? JSONDecoder().decode(PermissionRequest.self, from: data)
            else { continue }
            if now - request.ts > Self.staleSeconds {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            bySession[request.sessionId] = request
        }
        requestsBySession = bySession
    }
}
