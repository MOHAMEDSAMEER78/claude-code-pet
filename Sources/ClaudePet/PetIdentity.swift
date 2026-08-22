import Foundation

enum PetIdentity {
    static let builtInNames = ["Codey", "Seedy", "Rocky", "Dewey", "Fireball", "Stacky"]

    static func namePool(customPetDirs: [URL]) -> [String] {
        let customNames = customPetDirs.map { $0.lastPathComponent.capitalized }
        let pool = customNames + builtInNames
        return pool.isEmpty ? builtInNames : pool
    }

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

    static func identityKey(sessionId: String, cwd: String?, groupByProject: Bool) -> String {
        guard groupByProject, let cwd, !cwd.isEmpty else { return sessionId }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? sessionId : name
    }
}
