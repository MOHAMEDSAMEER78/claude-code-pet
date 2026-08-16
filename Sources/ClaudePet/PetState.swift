import Foundation

enum PetState: String, Codable {
    case idle
    case running
    case waitingPermission = "waiting-permission"
    case review
    case failed

    /// Higher = more urgent; used to pick which session's state "wins" when
    /// several sessions are active at once.
    var priority: Int {
        switch self {
        case .waitingPermission: return 4
        case .failed: return 3
        case .review: return 2
        case .running: return 1
        case .idle: return 0
        }
    }

    var emoji: String {
        switch self {
        case .idle: return "😴"
        case .running: return "🏃"
        case .waitingPermission: return "🙋"
        case .review: return "✅"
        case .failed: return "💥"
        }
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Working"
        case .waitingPermission: return "Needs permission"
        case .review: return "Ready for review"
        case .failed: return "Failed"
        }
    }
}

struct SessionStatus: Codable {
    var sessionId: String
    var state: PetState
    var cwd: String?
    var tool: String?
    var summary: String?
    var action: String?
    var ts: TimeInterval
    var terminalPid: Int32?
    var terminalApp: String?
    var tty: String?
    var tasksDone: Int?
    var tasksTotal: Int?
    var title: String?
    var claudePid: Int32?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case state, cwd, tool, summary, action, ts, tty, title
        case terminalPid = "terminal_pid"
        case terminalApp = "terminal_app"
        case tasksDone = "tasks_done"
        case tasksTotal = "tasks_total"
        case claudePid = "claude_pid"
    }
}
