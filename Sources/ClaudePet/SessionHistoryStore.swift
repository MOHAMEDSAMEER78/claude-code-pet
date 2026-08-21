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
        let entry = Entry(
            ts: endTs,
            sessionId: session.sessionId,
            title: session.title,
            cwd: session.cwd,
            finalState: session.state.rawValue,
            tasksCompleted: session.tasksDone ?? 0,
            tasksTotal: session.tasksTotal ?? 0,
            durationSeconds: session.startedTs.map { endTs - $0 }
        )
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

    private func readEntries() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL), let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap {
            $0.data(using: .utf8).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
        }
    }
}
