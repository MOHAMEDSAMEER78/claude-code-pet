import Foundation
import Combine

/// Tracks which custom pet (if any) is active. Scans ~/.claude/pets and
/// ~/.codex/pets; falls back to the built-in emoji when none is found or
/// selected.
final class PetLibrary: ObservableObject {
    @Published private(set) var current: PetAsset?
    @Published private(set) var availableDirs: [URL] = []
    @Published private(set) var selectedIndex: Int?

    init() {
        reload()
    }

    func reload() {
        availableDirs = PetAssetLoader.availablePets()
        if let idx = selectedIndex, idx < availableDirs.count {
            current = PetAssetLoader.load(from: availableDirs[idx])
        } else if let first = availableDirs.first {
            selectedIndex = 0
            current = PetAssetLoader.load(from: first)
        } else {
            selectedIndex = nil
            current = nil
        }
    }

    /// Jumps directly to a specific pet by index - used by the Pet Gallery,
    /// which shows every installed pet at once rather than cycling one at a
    /// time via the menu bar's "Next Pet".
    func select(index: Int) {
        guard availableDirs.indices.contains(index) else { return }
        selectedIndex = index
        current = PetAssetLoader.load(from: availableDirs[index])
    }

    func selectNext() {
        guard !availableDirs.isEmpty else { return }
        let next = ((selectedIndex ?? -1) + 1) % availableDirs.count
        selectedIndex = next
        current = PetAssetLoader.load(from: availableDirs[next])
    }

    func useEmoji() {
        selectedIndex = nil
        current = nil
    }
}
