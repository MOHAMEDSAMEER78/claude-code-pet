import Foundation
import Combine

final class PetLibrary: ObservableObject {
    @Published private(set) var current: PetAsset?
    @Published private(set) var availableDirs: [URL] = []
    @Published private(set) var selectedIndex: Int?
    @Published private(set) var perProjectSelection: [String: String] = [:]
    private var perProjectAssetCache: [String: PetAsset?] = [:]

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
