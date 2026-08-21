import Foundation
import Combine
import Darwin
import os
import ClaudePetCore

/// Watches ~/.claude/pet/sessions/*.json (one file per Claude Code session,
/// written by the pet-hook bridge script) and exposes both the per-session
/// state (for multi-pet mode) and an aggregate across all sessions
/// (for single-pet mode). File I/O and liveness-checking live here; the
/// actual "what should this session show right now" decisions are pure
/// functions in ClaudePetCore.SessionLogic so they're unit-testable.
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [EffectiveSession] = []
    @Published private(set) var aggregate: PetState = .idle
    @Published private(set) var bubbleText: String = ""
    @Published private(set) var sessionCount: Int = 0
    @Published private(set) var tasksDone: Int?
    @Published private(set) var tasksTotal: Int?
    @Published private(set) var title: String?
    /// Set whenever `refresh()` skips a session file it couldn't decode -
    /// visible (via Preferences/Stats) rather than silently vanishing that
    /// session, so a hook/app version mismatch doesn't look like a bug with
    /// no trace. Cleared once no file currently fails to decode.
    @Published private(set) var lastDecodeWarning: String?

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

    /// Fires whenever a session's state actually changes, carrying the old
    /// and new EffectiveSession - used to trigger notifications/sounds/history
    /// logging without those concerns living inside this store.
    let stateTransitions = PassthroughSubject<(old: EffectiveSession?, new: EffectiveSession), Never>()
    /// Fires once, with the ended session's last-known snapshot, right
    /// before its file is removed - the only hook point for session history.
    let sessionEnded = PassthroughSubject<EffectiveSession, Never>()

    private var lastStateBySession: [String: PetState] = [:]
    /// Push path: pet-hook.py pings this the instant it writes/removes a
    /// session file, so refresh() usually runs immediately rather than
    /// waiting on FSEvent or the poll-timer fallback below.
    private let notifier = IPCNotifier(socketName: "notify-sessions.sock")

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

        notifier.start { [weak self] in self?.refresh() }

        // Last-resort fallback if both the socket ping and the FSEvent watch
        // somehow miss a change (e.g. an old pet-hook.py version with
        // neither). Relaxed from 5s now that the socket ping above is the
        // primary push path - this only needs to catch the rare double-miss.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Drives the review->idle decay and stale-file cleanup even with no fs activity.
        decayTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let now = Date().timeIntervalSince1970
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []

        var statuses: [SessionStatus] = []
        var decodeWarning: String?
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file) else { continue }
            let status: SessionStatus
            switch SessionLogic.decodeStatus(data: data) {
            case .success(let decoded):
                status = decoded
            case .failure(let issue):
                switch issue {
                case .malformed:
                    os_log(.error, "ClaudePet: skipped unreadable session file %{public}@", file.lastPathComponent)
                case .unsupportedSchema(let found):
                    let message = "Session file \(file.lastPathComponent) uses a newer format (schema \(found)) than this build of ClaudePet understands - update the app."
                    os_log(.error, "ClaudePet: %{public}@", message)
                    decodeWarning = message
                }
                continue
            }

            // A session whose process has actually exited (crash, force-quit
            // terminal, killed mid-turn) never gets to run its own SessionEnd
            // hook, so its last state - often "running" - would otherwise sit
            // here for up to staleSeconds, outranking a real idle session in
            // the aggregate. Confirm liveness directly whenever we have a pid.
            if let pid = status.claudePid, kill(pid_t(pid), 0) != 0, errno == ESRCH {
                emitSessionEnded(for: status, now: now)
                try? FileManager.default.removeItem(at: file)
                continue
            }

            if SessionLogic.isStale(status: status, now: now, staleSeconds: Self.staleSeconds) {
                emitSessionEnded(for: status, now: now)
                try? FileManager.default.removeItem(at: file)
                continue
            }
            statuses.append(status)
        }

        let effective: [EffectiveSession] = statuses.map { s in
            let state = SessionLogic.effectiveState(status: s, now: now, reviewDecaySeconds: Self.reviewDecaySeconds)
            return EffectiveSession(
                sessionId: s.sessionId,
                state: state,
                bubbleText: SessionLogic.bubbleText(for: s, state: state),
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

        emitTransitions(for: effective)

        sessions = effective
        sessionCount = effective.count
        lastDecodeWarning = decodeWarning

        guard let winner = SessionLogic.winner(among: effective) else {
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

    private func emitTransitions(for effective: [EffectiveSession]) {
        var seen: Set<String> = []
        for session in effective {
            seen.insert(session.sessionId)
            let previous = lastStateBySession[session.sessionId]
            if previous != session.state {
                let oldSession = previous.map { old in
                    var s = session
                    s.state = old
                    return s
                }
                stateTransitions.send((old: oldSession, new: session))
                lastStateBySession[session.sessionId] = session.state
            }
        }
        for goneId in lastStateBySession.keys where !seen.contains(goneId) {
            lastStateBySession.removeValue(forKey: goneId)
        }
    }

    private func emitSessionEnded(for status: SessionStatus, now: TimeInterval) {
        let state = SessionLogic.effectiveState(status: status, now: now, reviewDecaySeconds: Self.reviewDecaySeconds)
        sessionEnded.send(EffectiveSession(
            sessionId: status.sessionId, state: state,
            bubbleText: SessionLogic.bubbleText(for: status, state: state),
            cwd: status.cwd, terminalPid: status.terminalPid, terminalApp: status.terminalApp,
            tty: status.tty, ts: status.ts, tasksDone: status.tasksDone, tasksTotal: status.tasksTotal,
            title: status.title, claudePid: status.claudePid
        ))
        lastStateBySession.removeValue(forKey: status.sessionId)
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
        sessionEnded.send(session)
        lastStateBySession.removeValue(forKey: session.sessionId)
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("\(session.sessionId).json")
        )
        refresh()
    }
}
