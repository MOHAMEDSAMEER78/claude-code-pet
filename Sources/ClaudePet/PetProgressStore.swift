import Foundation
import Combine
import ClaudePetCore

/// Live view of the pet's derived "mood" (streak/level), recomputed from
/// SessionHistoryStore whenever a session finishes. Kept separate from
/// SessionHistoryStore itself so UI that only cares about mood (the sprite
/// tint) doesn't need to know about the history log's file-backed API.
final class PetProgressStore: ObservableObject {
    @Published private(set) var progress: PetProgress

    private var cancellable: AnyCancellable?

    init(sessionStore: SessionStore, historyStore: SessionHistoryStore) {
        self.progress = historyStore.loadProgress()
        cancellable = sessionStore.sessionEnded
            .receive(on: DispatchQueue.main)
            // The history entry itself is written asynchronously (it snapshots
            // transcript usage off-thread) - a short delay avoids reading the
            // log before this particular session's line has landed.
            .delay(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.progress = historyStore.loadProgress()
            }
    }
}
