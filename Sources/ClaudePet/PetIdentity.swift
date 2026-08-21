import Foundation

/// Assigns each session a stable display name for its activity card, the way
/// Codex shows a different named pet per concurrent chat. We don't load a
/// distinct sprite per session (that would multiply asset loading for little
/// payoff) - just a distinct *name*, drawn from any installed custom pets
/// plus Codex's own documented built-in pet names as filler.
enum PetIdentity {
    static let builtInNames = ["Codey", "Seedy", "Rocky", "Dewey", "Fireball", "Stacky"]

    static func namePool(customPetDirs: [URL]) -> [String] {
        let customNames = customPetDirs.map { $0.lastPathComponent.capitalized }
        let pool = customNames + builtInNames
        return pool.isEmpty ? builtInNames : pool
    }

    /// A stable (not Swift's randomized hashValue) hash so the same session
    /// always gets the same name across app relaunches.
    private static func stableHash(_ s: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in s.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return hash
    }

    static func name(for sessionId: String, pool: [String]) -> String {
        guard !pool.isEmpty else { return "Pet" }
        let index = Int(stableHash(sessionId) % UInt64(pool.count))
        return pool[index]
    }

    /// Which string to hash the display name from: the session id (default -
    /// a distinct name per concurrent chat) or the project directory's name
    /// (so every session in the same repo shows the same pet, at the cost of
    /// two sessions in different repos being able to collide on a name).
    /// Falls back to the session id whenever there's no cwd to group by.
    static func identityKey(sessionId: String, cwd: String?, groupByProject: Bool) -> String {
        guard groupByProject, let cwd, !cwd.isEmpty else { return sessionId }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? sessionId : name
    }
}
