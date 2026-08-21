import Foundation
import Testing
@testable import ClaudePetCore

struct HistoryLogicTests {
    private func entry(ts: TimeInterval, tasksCompleted: Int = 0) -> HistoryEntry {
        HistoryEntry(
            ts: ts, sessionId: "s", title: nil, cwd: nil,
            finalState: "idle", tasksCompleted: tasksCompleted, tasksTotal: 0
        )
    }

    private var referenceNow: Date { Date(timeIntervalSince1970: 1_700_000_000) }
    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    // MARK: - stats

    @Test func countsOnlyTodaysEntriesForSessionsToday() {
        let now = referenceNow
        let startOfToday = calendar.startOfDay(for: now).timeIntervalSince1970
        let entries = [
            entry(ts: startOfToday + 10), // today
            entry(ts: startOfToday - 10), // yesterday
        ]
        let stats = HistoryLogic.stats(from: entries, now: now, calendar: calendar)
        #expect(stats.sessionsToday == 1)
    }

    @Test func countsLastSevenDaysForSessionsThisWeek() {
        let now = referenceNow
        let eightDaysAgo = calendar.date(byAdding: .day, value: -8, to: now)!.timeIntervalSince1970
        let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: now)!.timeIntervalSince1970
        let entries = [entry(ts: sixDaysAgo), entry(ts: eightDaysAgo)]
        let stats = HistoryLogic.stats(from: entries, now: now, calendar: calendar)
        #expect(stats.sessionsThisWeek == 1)
    }

    @Test func sumsTasksCompletedAcrossTheWeek() {
        let now = referenceNow
        let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: now)!.timeIntervalSince1970
        let entries = [entry(ts: sixDaysAgo, tasksCompleted: 3), entry(ts: now.timeIntervalSince1970, tasksCompleted: 2)]
        let stats = HistoryLogic.stats(from: entries, now: now, calendar: calendar)
        #expect(stats.tasksCompletedThisWeek == 5)
    }

    @Test func emptyEntriesProduceZeroedStats() {
        let stats = HistoryLogic.stats(from: [], now: referenceNow, calendar: calendar)
        #expect(stats == HistoryStats(sessionsToday: 0, sessionsThisWeek: 0, tasksCompletedThisWeek: 0))
    }
}
