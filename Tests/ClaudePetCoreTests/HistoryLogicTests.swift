import Foundation
import Testing
@testable import ClaudePetCore

struct HistoryLogicTests {
    private func entry(
        ts: TimeInterval, tasksCompleted: Int = 0, durationSeconds: TimeInterval? = nil,
        cwd: String? = nil, costUSD: Double? = nil
    ) -> HistoryEntry {
        HistoryEntry(
            ts: ts, sessionId: "s", title: nil, cwd: cwd,
            finalState: "idle", tasksCompleted: tasksCompleted, tasksTotal: 0,
            durationSeconds: durationSeconds, costUSD: costUSD
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

    @Test func sumsKnownDurationsWithinToday() {
        let now = referenceNow
        let startOfToday = calendar.startOfDay(for: now).timeIntervalSince1970
        let entries = [
            entry(ts: startOfToday + 10, durationSeconds: 600),
            entry(ts: startOfToday + 20, durationSeconds: nil), // no started_ts - contributes 0
        ]
        let stats = HistoryLogic.stats(from: entries, now: now, calendar: calendar)
        #expect(stats.secondsWorkedToday == 600)
    }

    @Test func sumsKnownDurationsWithinTheWeek() {
        let now = referenceNow
        let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: now)!.timeIntervalSince1970
        let entries = [entry(ts: sixDaysAgo, durationSeconds: 1800), entry(ts: now.timeIntervalSince1970, durationSeconds: 300)]
        let stats = HistoryLogic.stats(from: entries, now: now, calendar: calendar)
        #expect(stats.secondsWorkedThisWeek == 2100)
    }

    @Test func emptyEntriesProduceZeroedStats() {
        let stats = HistoryLogic.stats(from: [], now: referenceNow, calendar: calendar)
        #expect(stats == HistoryStats(sessionsToday: 0, sessionsThisWeek: 0, tasksCompletedThisWeek: 0))
    }

    // MARK: - currentStreak

    @Test func streakCountsBackFromTodayWhenTodayHasASession() {
        let now = referenceNow
        let startOfToday = calendar.startOfDay(for: now).timeIntervalSince1970
        let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now)!.timeIntervalSince1970
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!.timeIntervalSince1970
        let entries = [entry(ts: startOfToday + 5), entry(ts: oneDayAgo), entry(ts: twoDaysAgo)]
        #expect(HistoryLogic.currentStreak(from: entries, now: now, calendar: calendar) == 3)
    }

    @Test func streakStillCountsYesterdayWhenNothingRecordedYetToday() {
        let now = referenceNow
        let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now)!.timeIntervalSince1970
        #expect(HistoryLogic.currentStreak(from: [entry(ts: oneDayAgo)], now: now, calendar: calendar) == 1)
    }

    @Test func streakBreaksOnAGapDay() {
        let now = referenceNow
        let startOfToday = calendar.startOfDay(for: now).timeIntervalSince1970
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!.timeIntervalSince1970
        let entries = [entry(ts: startOfToday + 5), entry(ts: twoDaysAgo)] // yesterday missing
        #expect(HistoryLogic.currentStreak(from: entries, now: now, calendar: calendar) == 1)
    }

    @Test func streakIsZeroWithNoEntries() {
        #expect(HistoryLogic.currentStreak(from: [], now: referenceNow, calendar: calendar) == 0)
    }

    // MARK: - progress

    @Test func progressComputesXpFromTasksAndSessions() {
        let entries = [entry(ts: referenceNow.timeIntervalSince1970, tasksCompleted: 4)]
        let progress = HistoryLogic.progress(from: entries, now: referenceNow, calendar: calendar)
        #expect(progress.totalSessions == 1)
        #expect(progress.totalTasksCompleted == 4)
        #expect(progress.xp == 45) // 4*10 + 1*5
        #expect(progress.level == 0) // sqrt(45/100) floors to 0
    }

    @Test func progressLevelsUpPastXpThreshold() {
        // 10 sessions * 5 xp each + enough tasks to clear the level-1 threshold (100 xp).
        let entries = (0..<10).map { entry(ts: referenceNow.timeIntervalSince1970, tasksCompleted: 5) }
        let progress = HistoryLogic.progress(from: entries, now: referenceNow, calendar: calendar)
        #expect(progress.xp == 550)
        #expect(progress.level == 2) // sqrt(550/100) = sqrt(5.5) ~= 2.34 -> 2
    }

    // MARK: - dailyBuckets

    @Test func dailyBucketsGroupEntriesByCalendarDayOldestFirst() {
        let now = referenceNow
        let startOfToday = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let entries = [
            entry(ts: startOfToday.timeIntervalSince1970 + 5, costUSD: 1.0),
            entry(ts: yesterday.timeIntervalSince1970 + 5, costUSD: 2.0),
        ]
        let buckets = HistoryLogic.dailyBuckets(from: entries, days: 2, now: now, calendar: calendar)
        #expect(buckets.count == 2)
        #expect(buckets.first?.date == yesterday)
        #expect(buckets.first?.costUSD == 2.0)
        #expect(buckets.last?.date == startOfToday)
        #expect(buckets.last?.costUSD == 1.0)
    }

    @Test func dailyBucketsIncludeEmptyDaysAtZero() {
        let buckets = HistoryLogic.dailyBuckets(from: [], days: 3, now: referenceNow, calendar: calendar)
        #expect(buckets.count == 3)
        #expect(buckets.allSatisfy { $0.sessions == 0 && $0.costUSD == 0 })
    }

    // MARK: - perProjectTotals

    @Test func perProjectTotalsGroupByCwdBasenameSortedByCost() {
        let entries = [
            entry(ts: 1, cwd: "/Users/x/projA", costUSD: 1.0),
            entry(ts: 2, cwd: "/Users/x/projB", costUSD: 5.0),
            entry(ts: 3, cwd: "/Users/x/projA", costUSD: 1.5),
        ]
        let totals = HistoryLogic.perProjectTotals(from: entries)
        #expect(totals.count == 2)
        #expect(totals.first?.project == "projB")
        #expect(totals.first?.costUSD == 5.0)
        #expect(totals.last?.project == "projA")
        #expect(totals.last?.sessions == 2)
    }

    @Test func perProjectTotalsGroupMissingCwdAsUnknown() {
        let totals = HistoryLogic.perProjectTotals(from: [entry(ts: 1, cwd: nil, costUSD: 3.0)])
        #expect(totals == [ProjectTotal(project: "Unknown", costUSD: 3.0, sessions: 1)])
    }
}
