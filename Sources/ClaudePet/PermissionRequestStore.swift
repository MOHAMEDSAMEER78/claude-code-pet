import Foundation
import Combine
import ClaudePetCore

final class PermissionRequestStore: ObservableObject {
    @Published private(set) var requestsBySession: [String: PermissionRequest] = [:]

    private let requestsDir: URL
    private var dirWatcher: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private let notifier = IPCNotifier(socketName: "notify-requests.sock")

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
