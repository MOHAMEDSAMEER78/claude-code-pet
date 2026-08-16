import Foundation
import Combine
import Darwin

/// A session's live-decayed view state, derived from its SessionStatus file.
struct EffectiveSession: Identifiable {
    var id: String { sessionId }
    var sessionId: String
    var state: PetState
    var bubbleText: String
    var cwd: String?
    var terminalPid: Int32?
    var terminalApp: String?
    var tty: String?
    var ts: TimeInterval
    var tasksDone: Int?
    var tasksTotal: Int?
    var title: String?
    var claudePid: Int32?
}

/// Watches ~/.claude/pet/sessions/*.json (one file per Claude Code session,
/// written by the pet-hook bridge script) and exposes both the per-session
/// state (for multi-pet mode) and an aggregate across all sessions
/// (for single-pet mode).
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [EffectiveSession] = []
    @Published private(set) var aggregate: PetState = .idle
    @Published private(set) var bubbleText: String = ""
    @Published private(set) var sessionCount: Int = 0
    @Published private(set) var tasksDone: Int?
    @Published private(set) var tasksTotal: Int?
    @Published private(set) var title: String?

    private let directory: URL
    private var dirWatcher: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var decayTimer: Timer?

    /// A "review" state older than this decays to idle in the UI.
    private static let reviewDecaySeconds: TimeInterval = 20
    /// Fallback for sessions with no resolvable claude_pid to liveness-check
    /// (e.g. daemon/forked sessions) - much shorter than before, since the
    /// pid check below is what actually catches most dead sessions promptly.
    private static let staleSeconds: TimeInterval = 30 * 60

    init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/pet/sessions", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        startWatching()
        refresh()
    }

    private func startWatching() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in self?.refresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.dirWatcher = source

        // Poll fallback in case an FSEvent is missed or the watched fd goes stale.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Drives the review->idle decay and stale-file cleanup even with no fs activity.
        decayTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func bubble(for status: SessionStatus, state: PetState) -> String {
        let cwdName = status.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        var parts = [String]()
        if !cwdName.isEmpty { parts.append(cwdName) }
        if let tool = status.tool, !tool.isEmpty { parts.append(tool) }
        if let summary = status.summary, !summary.isEmpty { parts.append(summary) }
        return parts.isEmpty ? state.label : parts.joined(separator: " · ")
    }

    private func refresh() {
        let now = Date().timeIntervalSince1970
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []

        var statuses: [SessionStatus] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let status = try? JSONDecoder().decode(SessionStatus.self, from: data)
            else { continue }

            // A session whose process has actually exited (crash, force-quit
            // terminal, killed mid-turn) never gets to run its own SessionEnd
            // hook, so its last state - often "running" - would otherwise sit
            // here for up to staleSeconds, outranking a real idle session in
            // the aggregate. Confirm liveness directly whenever we have a pid.
            if let pid = status.claudePid, kill(pid_t(pid), 0) != 0, errno == ESRCH {
                try? FileManager.default.removeItem(at: file)
                continue
            }

            if now - status.ts > Self.staleSeconds {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            statuses.append(status)
        }

        let effective: [EffectiveSession] = statuses.map { s in
            let state = (s.state == .review && now - s.ts > Self.reviewDecaySeconds) ? .idle : s.state
            return EffectiveSession(
                sessionId: s.sessionId,
                state: state,
                bubbleText: bubble(for: s, state: state),
                cwd: s.cwd,
                terminalPid: s.terminalPid,
                terminalApp: s.terminalApp,
                tty: s.tty,
                ts: s.ts,
                tasksDone: s.tasksDone,
                tasksTotal: s.tasksTotal,
                title: s.title,
                claudePid: s.claudePid
            )
        }.sorted { $0.ts < $1.ts }

        sessions = effective
        sessionCount = effective.count

        guard let winner = effective.max(by: { $0.state.priority < $1.state.priority }) else {
            aggregate = .idle
            bubbleText = ""
            tasksDone = nil
            tasksTotal = nil
            title = nil
            return
        }
        aggregate = winner.state
        bubbleText = winner.bubbleText
        tasksDone = winner.tasksDone
        tasksTotal = winner.tasksTotal
        title = winner.title
    }

    /// Ends a Claude Code session from the tray, mirroring "close tab": sends
    /// SIGTERM to the resolved CLI process (falls back to SIGKILL if it's
    /// still alive after a beat), then removes the session file immediately
    /// so the tray updates without waiting on SessionEnd - a forcibly-killed
    /// process never gets to run its own SessionEnd hook.
    func killSession(_ session: EffectiveSession) {
        if let pid = session.claudePid {
            kill(pid_t(pid), SIGTERM)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if kill(pid_t(pid), 0) == 0 { // still alive - process ignored SIGTERM
                    kill(pid_t(pid), SIGKILL)
                }
            }
        }
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("\(session.sessionId).json")
        )
        refresh()
    }
}
