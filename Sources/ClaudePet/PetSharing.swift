import Foundation

enum PetSharing {
    enum ShareError: Error {
        case dittoFailed
        case noPetFolderInArchive
    }

    static func export(petDir: URL, to destinationZip: URL) throws {
        try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", petDir.path, destinationZip.path])
    }

    @discardableResult
    static func importPet(fromZip zipURL: URL) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, tempDir.path])

        guard let sourceDir = findPetFolder(in: tempDir) else { throw ShareError.noPetFolderInArchive }

        let petsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/pets", isDirectory: true)
        try FileManager.default.createDirectory(at: petsDir, withIntermediateDirectories: true)

        let baseName = sourceDir.lastPathComponent
        var destination = petsDir.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = petsDir.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try FileManager.default.copyItem(at: sourceDir, to: destination)
        return destination.lastPathComponent
    }

    private static func findPetFolder(in root: URL) -> URL? {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("pet.json").path) {
            return root
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for entry in entries {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }
            if FileManager.default.fileExists(atPath: entry.appendingPathComponent("pet.json").path) {
                return entry
            }
        }
        return nil
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ShareError.dittoFailed }
    }
}
