import Foundation
import Combine

/// Watches ~/.claude/pet/requests/*.json for pending permission decisions
/// and writes ~/.claude/pet/responses/<id>.json when the user answers from
/// the pet's Allow/Deny bubble. The blocked pet-hook.py process polls for
/// the response file and relays the decision back to Claude Code.
final class PermissionRequestStore: ObservableObject {
    @Published private(set) var requestsBySession: [String: PermissionRequest] = [:]

    private let requestsDir: URL
    private let responsesDir: URL
    private var dirWatcher: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?

    /// Requests older than this are assumed to have already timed out on
    /// the hook side; stop showing their bubble. Kept just a bit above
    /// pet-hook.py's own AWAIT_PERMISSION_TIMEOUT_SECONDS (45s) - the hook
    /// normally removes its own request file on timeout, this is only a
    /// backstop for the rare case it didn't get to (e.g. force-killed).
    private static let staleSeconds: TimeInterval = 60

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        requestsDir = home.appendingPathComponent(".claude/pet/requests", isDirectory: true)
        responsesDir = home.appendingPathComponent(".claude/pet/responses", isDirectory: true)
        try? FileManager.default.createDirectory(at: requestsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: responsesDir, withIntermediateDirectories: true)
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

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
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

    func respond(_ request: PermissionRequest, allow: Bool) {
        let response: [String: Any] = ["decision": allow ? "allow" : "deny"]
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }
        try? data.write(to: responsesDir.appendingPathComponent("\(request.requestId).json"))
        // Clear immediately so the bubble disappears without waiting on the
        // hook process to notice and clean up.
        try? FileManager.default.removeItem(at: requestsDir.appendingPathComponent("\(request.requestId).json"))
        requestsBySession.removeValue(forKey: request.sessionId)
    }
}
