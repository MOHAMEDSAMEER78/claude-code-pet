import Foundation
import Combine

/// Tracks which custom pet (if any) is active. Scans ~/.claude/pets and
/// ~/.codex/pets; falls back to the built-in emoji when none is found or
/// selected.
final class PetLibrary: ObservableObject {
    @Published private(set) var current: PetAsset?
    @Published private(set) var availableDirs: [URL] = []
    @Published private(set) var selectedIndex: Int?
    /// project key (see PetIdentity.identityKey) -> folder name, or the
    /// emoji sentinel. Only consulted by callers that resolve a per-project
    /// asset via `asset(forKey:)`; everything else keeps using the single
    /// global `current` exactly as before.
    @Published private(set) var perProjectSelection: [String: String] = [:]
    private var perProjectAssetCache: [String: PetAsset?] = [:]

    /// Folder names (not indices) so the choice survives relaunches even if
    /// `availablePets()` returns entries in a different order next time -
    /// `contentsOfDirectory` makes no ordering guarantee. `nil` means "use
    /// the built-in emoji", stored as an explicit sentinel so it's
    /// distinguishable from "never chosen".
    private static let selectionKey = "selectedPetIdentifier"
    private static let perProjectSelectionKey = "perProjectPetSelection"
    private static let emojiSentinel = "__emoji__"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        availableDirs = PetAssetLoader.availablePets()
        let stored = defaults.string(forKey: Self.selectionKey)
        if stored == Self.emojiSentinel {
            selectedIndex = nil
            current = nil
        } else if let stored, let idx = availableDirs.firstIndex(where: { $0.lastPathComponent == stored }) {
            selectedIndex = idx
            current = PetAssetLoader.load(from: availableDirs[idx])
        } else if let first = availableDirs.first {
            selectedIndex = 0
            current = PetAssetLoader.load(from: first)
            persistSelection(for: first)
        } else {
            selectedIndex = nil
            current = nil
        }

        if let data = defaults.data(forKey: Self.perProjectSelectionKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            perProjectSelection = decoded
        } else {
            perProjectSelection = [:]
        }
        perProjectAssetCache.removeAll()
    }

    /// Resolves the asset for a given project/session key (from
    /// `PetIdentity.identityKey`): an explicit per-project override if one
    /// exists, else the global default (`current`). Pass `nil` to always get
    /// the global default.
    func asset(forKey key: String?) -> PetAsset? {
        guard let key, let selection = perProjectSelection[key] else { return current }
        if let cached = perProjectAssetCache[key] { return cached }
        let resolved: PetAsset?
        if selection == Self.emojiSentinel {
            resolved = nil
        } else if let dir = availableDirs.first(where: { $0.lastPathComponent == selection }) {
            resolved = PetAssetLoader.load(from: dir)
        } else {
            resolved = nil
        }
        perProjectAssetCache[key] = resolved
        return resolved
    }

    /// Sets (or, with `dirName: nil`, clears back to the global default) the
    /// pet override for one project key.
    func setSelection(forKey key: String, dirName: String?) {
        if let dirName {
            perProjectSelection[key] = dirName
        } else {
            perProjectSelection.removeValue(forKey: key)
        }
        perProjectAssetCache.removeValue(forKey: key)
        persistPerProjectSelection()
    }

    func useEmoji(forKey key: String) {
        setSelection(forKey: key, dirName: Self.emojiSentinel)
    }

    func isEmojiOverride(forKey key: String) -> Bool {
        perProjectSelection[key] == Self.emojiSentinel
    }

    private func persistPerProjectSelection() {
        guard let data = try? JSONEncoder().encode(perProjectSelection) else { return }
        defaults.set(data, forKey: Self.perProjectSelectionKey)
    }

    /// Jumps directly to a specific pet by index - used by the Pet Gallery,
    /// which shows every installed pet at once rather than cycling one at a
    /// time via the menu bar's "Next Pet".
    func select(index: Int) {
        guard availableDirs.indices.contains(index) else { return }
        selectedIndex = index
        current = PetAssetLoader.load(from: availableDirs[index])
        persistSelection(for: availableDirs[index])
    }

    func selectNext() {
        guard !availableDirs.isEmpty else { return }
        let next = ((selectedIndex ?? -1) + 1) % availableDirs.count
        selectedIndex = next
        current = PetAssetLoader.load(from: availableDirs[next])
        persistSelection(for: availableDirs[next])
    }

    func useEmoji() {
        selectedIndex = nil
        current = nil
        defaults.set(Self.emojiSentinel, forKey: Self.selectionKey)
    }

    private func persistSelection(for dir: URL) {
        defaults.set(dir.lastPathComponent, forKey: Self.selectionKey)
    }
}
