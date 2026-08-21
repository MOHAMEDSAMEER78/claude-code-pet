import Foundation

/// One completed Claude Code session, as appended to the local
/// history.jsonl log. `ts` is the record time (when the entry was written),
/// not a trustworthy session-start time - `durationSeconds` is only
/// populated when the session's file carried a `started_ts` (frozen to the
/// session's first-ever hook write), so older/mid-flight sessions without
/// one simply omit a duration rather than guessing.
public struct HistoryEntry: Codable {
    public var ts: TimeInterval
    public var sessionId: String
    public var title: String?
    public var cwd: String?
    public var finalState: String
    public var tasksCompleted: Int
    public var tasksTotal: Int
    public var durationSeconds: TimeInterval?

    public init(
        ts: TimeInterval, sessionId: String, title: String?, cwd: String?,
        finalState: String, tasksCompleted: Int, tasksTotal: Int,
        durationSeconds: TimeInterval? = nil
    ) {
        self.ts = ts
        self.sessionId = sessionId
        self.title = title
        self.cwd = cwd
        self.finalState = finalState
        self.tasksCompleted = tasksCompleted
        self.tasksTotal = tasksTotal
        self.durationSeconds = durationSeconds
    }
}

public struct HistoryStats: Equatable {
    public var sessionsToday: Int
    public var sessionsThisWeek: Int
    public var tasksCompletedThisWeek: Int
    /// Sum of `durationSeconds` across entries with a known duration only -
    /// entries without one (no started_ts) contribute nothing, rather than
    /// being estimated.
    public var secondsWorkedToday: TimeInterval
    public var secondsWorkedThisWeek: TimeInterval

    public init(
        sessionsToday: Int, sessionsThisWeek: Int, tasksCompletedThisWeek: Int,
        secondsWorkedToday: TimeInterval = 0, secondsWorkedThisWeek: TimeInterval = 0
    ) {
        self.sessionsToday = sessionsToday
        self.sessionsThisWeek = sessionsThisWeek
        self.tasksCompletedThisWeek = tasksCompletedThisWeek
        self.secondsWorkedToday = secondsWorkedToday
        self.secondsWorkedThisWeek = secondsWorkedThisWeek
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
            tasksCompletedThisWeek: week.reduce(0) { $0 + $1.tasksCompleted },
            secondsWorkedToday: today.reduce(0) { $0 + ($1.durationSeconds ?? 0) },
            secondsWorkedThisWeek: week.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        )
    }
}
