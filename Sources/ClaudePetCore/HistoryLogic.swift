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
    /// Snapshotted from the session's transcript at end-of-session (best
    /// effort - `nil` for entries recorded before this field existed, or if
    /// the transcript couldn't be read in time). Never re-derived later:
    /// Claude Code may prune/rotate transcript files after a session ends.
    public var costUSD: Double?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var model: String?

    public init(
        ts: TimeInterval, sessionId: String, title: String?, cwd: String?,
        finalState: String, tasksCompleted: Int, tasksTotal: Int,
        durationSeconds: TimeInterval? = nil,
        costUSD: Double? = nil, inputTokens: Int? = nil, outputTokens: Int? = nil, model: String? = nil
    ) {
        self.ts = ts
        self.sessionId = sessionId
        self.title = title
        self.cwd = cwd
        self.finalState = finalState
        self.tasksCompleted = tasksCompleted
        self.tasksTotal = tasksTotal
        self.durationSeconds = durationSeconds
        self.costUSD = costUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.model = model
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

/// A pet's derived "mood": how many sessions/tasks the user has ever
/// finished, and their current daily streak. Recomputed live from
/// history.jsonl on every read, same as HistoryStats - there's no separate
/// persisted aggregate to keep in sync.
public struct PetProgress: Equatable {
    public var totalSessions: Int
    public var totalTasksCompleted: Int
    public var streakDays: Int
    public var xp: Int
    public var level: Int

    public init(totalSessions: Int, totalTasksCompleted: Int, streakDays: Int, xp: Int, level: Int) {
        self.totalSessions = totalSessions
        self.totalTasksCompleted = totalTasksCompleted
        self.streakDays = streakDays
        self.xp = xp
        self.level = level
    }
}

public struct DailyBucket: Equatable {
    public var date: Date
    public var costUSD: Double
    public var secondsWorked: TimeInterval
    public var sessions: Int

    public init(date: Date, costUSD: Double, secondsWorked: TimeInterval, sessions: Int) {
        self.date = date
        self.costUSD = costUSD
        self.secondsWorked = secondsWorked
        self.sessions = sessions
    }
}

public struct ProjectTotal: Equatable {
    public var project: String
    public var costUSD: Double
    public var sessions: Int

    public init(project: String, costUSD: Double, sessions: Int) {
        self.project = project
        self.costUSD = costUSD
        self.sessions = sessions
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

    /// Count of consecutive calendar days (ending today or yesterday - a
    /// session yesterday but none yet today still counts as an active
    /// streak, since today isn't over) with at least one recorded session
    /// end. A day with zero sessions breaks the streak.
    public static func currentStreak(from entries: [HistoryEntry], now: Date, calendar: Calendar = .current) -> Int {
        guard !entries.isEmpty else { return 0 }
        let activeDays = Set(entries.map { calendar.startOfDay(for: Date(timeIntervalSince1970: $0.ts)) })
        var streak = 0
        var cursor = calendar.startOfDay(for: now)
        if !activeDays.contains(cursor) {
            // Nothing recorded yet today - that's fine, check if yesterday
            // keeps a streak alive; if not, the streak is simply 0.
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), activeDays.contains(yesterday) else {
                return 0
            }
            cursor = yesterday
        }
        while activeDays.contains(cursor) {
            streak += 1
            guard let prior = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prior
        }
        return streak
    }

    /// xp = 10 per completed task + 5 per finished session; level = floor(sqrt(xp/100)),
    /// i.e. level N requires (N^2 * 100) xp - deliberately simple and tunable in one place.
    public static func progress(from entries: [HistoryEntry], now: Date = Date(), calendar: Calendar = .current) -> PetProgress {
        let totalTasks = entries.reduce(0) { $0 + $1.tasksCompleted }
        let xp = totalTasks * 10 + entries.count * 5
        return PetProgress(
            totalSessions: entries.count,
            totalTasksCompleted: totalTasks,
            streakDays: currentStreak(from: entries, now: now, calendar: calendar),
            xp: xp,
            level: Int(Double(xp / 100).squareRoot())
        )
    }

    /// One bucket per calendar day over the trailing `days` days (oldest
    /// first), for a spend/time trend chart. Entries with no `costUSD` (pre-
    /// tracking, or unread transcript) contribute 0 to the sum but the
    /// session is still counted.
    public static func dailyBuckets(from entries: [HistoryEntry], days: Int, now: Date, calendar: Calendar = .current) -> [DailyBucket] {
        let startOfToday = calendar.startOfDay(for: now)
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: Date(timeIntervalSince1970: $0.ts)) }
        return (0..<days).reversed().compactMap { offset -> DailyBucket? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { return nil }
            let dayEntries = byDay[day] ?? []
            return DailyBucket(
                date: day,
                costUSD: dayEntries.reduce(0) { $0 + ($1.costUSD ?? 0) },
                secondsWorked: dayEntries.reduce(0) { $0 + ($1.durationSeconds ?? 0) },
                sessions: dayEntries.count
            )
        }
    }

    /// Total spend/session-count per project (cwd basename), sorted by
    /// highest spend first. Entries with no `cwd` are grouped under
    /// "Unknown".
    public static func perProjectTotals(from entries: [HistoryEntry]) -> [ProjectTotal] {
        let byProject = Dictionary(grouping: entries) { entry -> String in
            guard let cwd = entry.cwd, !cwd.isEmpty else { return "Unknown" }
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            return name.isEmpty ? "Unknown" : name
        }
        return byProject.map { project, entries in
            ProjectTotal(
                project: project,
                costUSD: entries.reduce(0) { $0 + ($1.costUSD ?? 0) },
                sessions: entries.count
            )
        }.sorted { $0.costUSD > $1.costUSD }
    }
}
