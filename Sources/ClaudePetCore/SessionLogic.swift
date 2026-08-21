import Foundation

/// A session's live-decayed view state, derived from its SessionStatus file.
public struct EffectiveSession: Identifiable {
    public var id: String { sessionId }
    public var sessionId: String
    public var state: PetState
    public var bubbleText: String
    public var cwd: String?
    public var terminalPid: Int32?
    public var terminalApp: String?
    public var tty: String?
    public var ts: TimeInterval
    public var tasksDone: Int?
    public var tasksTotal: Int?
    public var title: String?
    public var claudePid: Int32?

    public init(
        sessionId: String, state: PetState, bubbleText: String, cwd: String?,
        terminalPid: Int32?, terminalApp: String?, tty: String?, ts: TimeInterval,
        tasksDone: Int?, tasksTotal: Int?, title: String?, claudePid: Int32?
    ) {
        self.sessionId = sessionId
        self.state = state
        self.bubbleText = bubbleText
        self.cwd = cwd
        self.terminalPid = terminalPid
        self.terminalApp = terminalApp
        self.tty = tty
        self.ts = ts
        self.tasksDone = tasksDone
        self.tasksTotal = tasksTotal
        self.title = title
        self.claudePid = claudePid
    }
}

/// Pure decision logic for turning raw on-disk SessionStatus records into
/// what the UI should actually show - no file I/O, no AppKit, no timers.
/// Extracted from SessionStore so it can be unit tested without a live
/// filesystem watcher or process table.
public enum SessionLogic {
    /// The newest session/request-file shape this build understands. Bump
    /// alongside `SCHEMA_VERSION` in hooks/pet-hook.py whenever a field is
    /// renamed/removed/reinterpreted in a way an older build couldn't decode.
    public static let currentSchemaVersion = 1

    /// Why a session/request file's data didn't decode into a usable value -
    /// distinct from a plain "the JSON was garbage" failure so the caller can
    /// log something more useful than a silent skip.
    public enum DecodeIssue: Equatable, Error {
        case malformed
        case unsupportedSchema(found: Int)
    }

    /// Checks the on-disk `schema` field (via JSONSerialization, ahead of the
    /// strongly-typed decode below) before attempting to decode into
    /// `SessionStatus` - a session file written by a *newer* pet-hook.py than
    /// this build understands should be skipped with a visible reason, not
    /// silently dropped like any other malformed file. Missing/absent
    /// `schema` (pre-versioning files) is treated as schema 0, always
    /// supported.
    public static func decodeStatus(data: Data) -> Result<SessionStatus, DecodeIssue> {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let schema = obj["schema"] as? Int, schema > currentSchemaVersion {
            return .failure(.unsupportedSchema(found: schema))
        }
        guard let status = try? JSONDecoder().decode(SessionStatus.self, from: data) else {
            return .failure(.malformed)
        }
        return .success(status)
    }

    /// A "review" state older than `reviewDecaySeconds` decays to idle in the
    /// UI - Claude Code's own `idle_prompt` notification is unreliable, so
    /// the app times this out locally instead of depending on it.
    public static func effectiveState(status: SessionStatus, now: TimeInterval, reviewDecaySeconds: TimeInterval) -> PetState {
        (status.state == .review && now - status.ts > reviewDecaySeconds) ? .idle : status.state
    }

    /// True once a session's file is old enough that it's presumed abandoned
    /// (its process never got to run its own SessionEnd hook). This is only
    /// a fallback for sessions with no resolvable pid - a live pid is
    /// checked directly wherever `kill(pid, 0)` is available.
    public static func isStale(status: SessionStatus, now: TimeInterval, staleSeconds: TimeInterval) -> Bool {
        now - status.ts > staleSeconds
    }

    /// Prefers the hook's natural-language `action` sentence (e.g. "Editing
    /// SessionStore.swift") over the raw "cwd · tool · arg" join, which only
    /// remains as a fallback for session files written before `action`
    /// existed.
    public static func bubbleText(for status: SessionStatus, state: PetState) -> String {
        if let action = status.action, !action.isEmpty { return action }
        let cwdName = status.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        var parts = [String]()
        if !cwdName.isEmpty { parts.append(cwdName) }
        if let tool = status.tool, !tool.isEmpty { parts.append(tool) }
        if let summary = status.summary, !summary.isEmpty { parts.append(summary) }
        return parts.isEmpty ? state.label : parts.joined(separator: " · ")
    }

    /// Which session's state "wins" for the single aggregate pet: highest
    /// priority (needs-permission > failed > ready-for-review > running >
    /// idle), ties broken by whichever has been in that state longest.
    public static func winner(among sessions: [EffectiveSession]) -> EffectiveSession? {
        sessions.max { $0.state.priority < $1.state.priority }
    }
}
