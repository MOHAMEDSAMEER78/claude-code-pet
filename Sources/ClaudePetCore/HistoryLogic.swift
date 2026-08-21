import Foundation

/// One completed Claude Code session, as appended to the local
/// history.jsonl log. Deliberately carries no duration/elapsed-time field -
/// `ts` is the record time (when the entry was written), not a trustworthy
/// session-start time, so a duration would mean inventing data the hook
/// payloads don't actually give.
public struct HistoryEntry: Codable {
    public var ts: TimeInterval
    public var sessionId: String
    public var title: String?
    public var cwd: String?
    public var finalState: String
    public var tasksCompleted: Int
    public var tasksTotal: Int

    public init(
        ts: TimeInterval, sessionId: String, title: String?, cwd: String?,
        finalState: String, tasksCompleted: Int, tasksTotal: Int
    ) {
        self.ts = ts
        self.sessionId = sessionId
        self.title = title
        self.cwd = cwd
        self.finalState = finalState
        self.tasksCompleted = tasksCompleted
        self.tasksTotal = tasksTotal
    }
}

public struct HistoryStats: Equatable {
    public var sessionsToday: Int
    public var sessionsThisWeek: Int
    public var tasksCompletedThisWeek: Int

    public init(sessionsToday: Int, sessionsThisWeek: Int, tasksCompletedThisWeek: Int) {
        self.sessionsToday = sessionsToday
        self.sessionsThisWeek = sessionsThisWeek
        self.tasksCompletedThisWeek = tasksCompletedThisWeek
    }
}

/// Pure counting logic over history entries - no file I/O - extracted from
/// SessionHistoryStore so it's unit-testable without a live history.jsonl.
public enum HistoryLogic {
    public static func stats(from entries: [HistoryEntry], now: Date, calendar: Calendar = .current) -> HistoryStats {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: now) ?? startOfToday

        let today = entries.filter { $0.ts >= startOfToday.timeIntervalSince1970 }
        let week = entries.filter { $0.ts >= startOfWeek.timeIntervalSince1970 }

        return HistoryStats(
            sessionsToday: today.count,
            sessionsThisWeek: week.count,
            tasksCompletedThisWeek: week.reduce(0) { $0 + $1.tasksCompleted }
        )
    }
}
