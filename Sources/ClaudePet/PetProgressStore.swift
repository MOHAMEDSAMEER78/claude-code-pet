import Foundation
import Combine
import ClaudePetCore

final class PetProgressStore: ObservableObject {
    @Published private(set) var progress: PetProgress

    private var cancellable: AnyCancellable?

    init(sessionStore: SessionStore, historyStore: SessionHistoryStore) {
        self.progress = historyStore.loadProgress()
        cancellable = sessionStore.sessionEnded
            .receive(on: DispatchQueue.main)
            .delay(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.progress = historyStore.loadProgress()
            }
    }
}
