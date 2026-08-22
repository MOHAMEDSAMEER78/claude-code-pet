import Foundation

public enum PetState: String, Codable, CaseIterable {
    case idle
    case running
    case waitingPermission = "waiting-permission"
    case review
    case failed

    /// Higher = more urgent; used to pick which session's state "wins" when
    /// several sessions are active at once.
    public var priority: Int {
        switch self {
        case .waitingPermission: return 4
        case .failed: return 3
        case .review: return 2
        case .running: return 1
        case .idle: return 0
        }
    }

    public var emoji: String {
        switch self {
        case .idle: return "😴"
        case .running: return "🏃"
        case .waitingPermission: return "🙋"
        case .review: return "✅"
        case .failed: return "💥"
        }
    }

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Working"
        case .waitingPermission: return "Needs permission"
        case .review: return "Ready for review"
        case .failed: return "Failed"
        }
    }

    /// SF Symbol shown in the menu bar for this state - lets the status item
    /// itself communicate at a glance without opening the pet panel.
    public var menuBarSymbol: String {
        switch self {
        case .idle: return "pawprint.fill"
        case .running: return "figure.run"
        case .waitingPermission: return "hand.raised.fill"
        case .review: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

public struct SessionStatus: Codable {
    public var sessionId: String
    public var state: PetState
    public var cwd: String?
    public var tool: String?
    public var summary: String?
    public var action: String?
    public var ts: TimeInterval
    public var terminalPid: Int32?
    public var terminalApp: String?
    public var tty: String?
    public var tasksDone: Int?
    public var tasksTotal: Int?
    public var title: String?
    public var claudePid: Int32?
    /// Frozen to this session's first-ever write (see pet-hook.py) - absent
    /// on session files written before this field existed, in which case
    /// "time worked" for that session simply isn't computed rather than
    /// guessed from a last-write timestamp.
    public var startedTs: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case state, cwd, tool, summary, action, ts, tty, title
        case terminalPid = "terminal_pid"
        case terminalApp = "terminal_app"
        case tasksDone = "tasks_done"
        case tasksTotal = "tasks_total"
        case claudePid = "claude_pid"
        case startedTs = "started_ts"
    }
}
