import Foundation

/// Export/import a custom pet folder (pet.json + spritesheet) as a single
/// .zip, so a pet installed under ~/.claude/pets/<name> can be handed to
/// someone else without them having to reconstruct the folder by hand. Uses
/// /usr/bin/ditto (already relied on by build_app.sh for the release zip)
/// rather than adding a zip library dependency - no new packaging format,
/// just an archive of the existing folder+manifest convention.
enum PetSharing {
    enum ShareError: Error {
        case dittoFailed
        case noPetFolderInArchive
    }

    /// Zips `petDir` (e.g. ~/.claude/pets/dragon) to `destinationZip`,
    /// preserving it as a single top-level folder inside the archive so
    /// unzipping it anywhere reproduces `<name>/pet.json` + spritesheet.
    static func export(petDir: URL, to destinationZip: URL) throws {
        try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", petDir.path, destinationZip.path])
    }

    /// Unzips `zipURL` into a temp directory, locates the folder containing
    /// pet.json inside it (top-level, or one level down if the zip wraps an
    /// extra directory), and moves it into ~/.claude/pets/<name>, resolving a
    /// name collision by appending "-2", "-3", etc. Returns the installed
    /// pet's directory name (for a "select it" affordance after import), or
    /// throws if the archive doesn't contain a pet.json anywhere shallow.
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

    /// pet.json may be directly in the extracted root or nested one level
    /// down (ditto/Finder-created zips commonly wrap a single top folder).
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
