import Foundation
import Combine
import ClaudePetCore

/// A local-only, append-only log of finished sessions. Previously a
/// session's entire record vanished the moment it ended (its status file
/// just gets deleted) - this is the smallest possible step toward "what did
/// I actually do today," without inventing data (like elapsed time) the
/// hook payloads don't actually give us a trustworthy way to compute.
final class SessionHistoryStore: ObservableObject {
    typealias Entry = HistoryEntry
    typealias Stats = HistoryStats

    private let fileURL: URL
    private var cancellables: Set<AnyCancellable> = []
    /// Transcript reads (potentially multi-MB) and the append-only file
    /// write both happen here, off the main thread the sessionEnded signal
    /// arrives on.
    private let ioQueue = DispatchQueue(label: "SessionHistoryStore.io", qos: .utility)

    init(sessionStore: SessionStore) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/pet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.jsonl")

        sessionStore.sessionEnded
            .sink { [weak self] session in self?.record(session) }
            .store(in: &cancellables)
    }

    private func record(_ session: EffectiveSession) {
        let endTs = Date().timeIntervalSince1970
        let sessionId = session.sessionId
        let title = session.title
        let cwd = session.cwd
        let finalState = session.state.rawValue
        let tasksCompleted = session.tasksDone ?? 0
        let tasksTotal = session.tasksTotal ?? 0
        let durationSeconds = session.startedTs.map { endTs - $0 }

        ioQueue.async { [weak self] in
            // Best-effort: the transcript is Claude Code's own file, untouched
            // by anything ClaudePet deletes, but may still be missing/short if
            // the model never replied. A miss just leaves cost/tokens nil.
            let usage = TranscriptUsage.totals(forSession: sessionId)
            let entry = Entry(
                ts: endTs, sessionId: sessionId, title: title, cwd: cwd,
                finalState: finalState, tasksCompleted: tasksCompleted, tasksTotal: tasksTotal,
                durationSeconds: durationSeconds,
                costUSD: usage?.estimatedCostUSD, inputTokens: usage?.inputTokens,
                outputTokens: usage?.outputTokens, model: usage?.model
            )
            self?.writeEntry(entry)
        }
    }

    private func writeEntry(_ entry: Entry) {
        guard let data = try? JSONEncoder().encode(entry), let line = String(data: data, encoding: .utf8) else { return }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            try? (line + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write((line + "\n").data(using: .utf8) ?? Data())
    }

    func loadStats(now: Date = Date()) -> Stats {
        HistoryLogic.stats(from: readEntries(), now: now)
    }

    func loadProgress(now: Date = Date()) -> PetProgress {
        HistoryLogic.progress(from: readEntries(), now: now)
    }

    func loadDailyBuckets(days: Int, now: Date = Date()) -> [DailyBucket] {
        HistoryLogic.dailyBuckets(from: readEntries(), days: days, now: now)
    }

    func loadProjectTotals() -> [ProjectTotal] {
        HistoryLogic.perProjectTotals(from: readEntries())
    }

    /// Sum of `costUSD` across every entry recorded today - used for the
    /// budget-alert check, combined by the caller with live spend from any
    /// still-active sessions.
    func todaysRecordedSpendUSD(now: Date = Date()) -> Double {
        let startOfToday = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        return readEntries().filter { $0.ts >= startOfToday }.reduce(0) { $0 + ($1.costUSD ?? 0) }
    }

    private func readEntries() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL), let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap {
            $0.data(using: .utf8).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
        }
    }
}
