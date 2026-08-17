import Foundation

/// One line of the hook-setup diagnostic checklist.
struct HookCheck: Identifiable {
    enum Status { case ok, warning, missing }
    let id = UUID()
    let title: String
    let status: Status
    let detail: String
}

/// Installs and diagnoses the hook↔app bridge. Previously the only install
/// path was "hand-merge a JSON snippet into ~/.claude/settings.json, pointing
/// at wherever you happened to clone the repo" - fragile (moving/deleting the
/// checkout silently breaks every hook) and a real barrier to anyone who
/// isn't comfortable editing JSON by hand.
///
/// This installs pet-hook.py to a fixed, checkout-independent location
/// (~/.claude/pet/bin/pet-hook.py) and points the hook config at that
/// instead, so the app keeps working even if the original git checkout it
/// was built from is moved or deleted.
enum HookInstaller {
    static let installedHookURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/pet/bin/pet-hook.py")
    private static let settingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
    /// The placeholder path baked into the bundled settings-snippet.json,
    /// rewritten at install time to `installedHookURL`.
    private static let placeholderPath = "~/claude-code-pet/hooks/pet-hook.py"

    enum InstallError: LocalizedError {
        case bundleResourceMissing(String)
        case settingsUnreadable
        case settingsUnwritable(Error)

        var errorDescription: String? {
            switch self {
            case .bundleResourceMissing(let name):
                return "Couldn't find \(name) bundled with the app."
            case .settingsUnreadable:
                return "~/.claude/settings.json exists but isn't valid JSON - fix or remove it first."
            case .settingsUnwritable(let error):
                return "Couldn't write ~/.claude/settings.json: \(error.localizedDescription)"
            }
        }
    }

    /// Copies the bundled hook script to its stable install location, merges
    /// the bundled hook config into ~/.claude/settings.json (backing it up
    /// first), and rewrites the placeholder path to the installed one.
    /// Existing unrelated hooks are preserved - matcher groups are appended,
    /// never replacing the event's existing entries wholesale.
    static func install() throws {
        guard let scriptData = Bundle.main.url(forResource: "pet-hook", withExtension: "py")
            .flatMap({ try? Data(contentsOf: $0) })
        else { throw InstallError.bundleResourceMissing("pet-hook.py") }
        guard let snippetURL = Bundle.main.url(forResource: "settings-snippet", withExtension: "json"),
              var snippetText = try? String(contentsOf: snippetURL, encoding: .utf8)
        else { throw InstallError.bundleResourceMissing("settings-snippet.json") }

        try FileManager.default.createDirectory(
            at: installedHookURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try scriptData.write(to: installedHookURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedHookURL.path)

        snippetText = snippetText.replacingOccurrences(of: placeholderPath, with: installedHookURL.path)
        guard let snippetData = snippetText.data(using: .utf8),
              let snippet = try? JSONSerialization.jsonObject(with: snippetData) as? [String: Any],
              let snippetHooks = snippet["hooks"] as? [String: Any]
        else { throw InstallError.bundleResourceMissing("settings-snippet.json") }

        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            guard let existingData = try? Data(contentsOf: settingsURL),
                  let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any]
            else { throw InstallError.settingsUnreadable }
            settings = existing
            let backupURL = settingsURL.appendingPathExtension("bak")
            try? existingData.write(to: backupURL)
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, groups) in snippetHooks {
            var existingGroups = hooks[event] as? [Any] ?? []
            if let newGroups = groups as? [Any] { existingGroups.append(contentsOf: newGroups) }
            hooks[event] = existingGroups
        }
        settings["hooks"] = hooks

        do {
            let output = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: settingsURL)
        } catch {
            throw InstallError.settingsUnwritable(error)
        }
    }

    /// Read-only health check, safe to run any time (including before
    /// install) - surfaced from the menu bar as "Diagnose Hooks…" so a "the
    /// pet just isn't reacting" report becomes self-serve.
    static func diagnose() -> [HookCheck] {
        var checks: [HookCheck] = []

        let scriptInstalled = FileManager.default.fileExists(atPath: installedHookURL.path)
        let scriptExecutable = FileManager.default.isExecutableFile(atPath: installedHookURL.path)
        if scriptInstalled && scriptExecutable {
            checks.append(HookCheck(title: "Hook script installed", status: .ok, detail: installedHookURL.path))
        } else if scriptInstalled {
            checks.append(HookCheck(title: "Hook script not executable", status: .warning, detail: installedHookURL.path))
        } else {
            checks.append(HookCheck(title: "Hook script not installed", status: .missing, detail: "Run setup to install it"))
        }

        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hooks = json["hooks"] as? [String: Any] {
            let commands = Self.allCommands(in: hooks)
            let wired = commands.contains { $0.contains("pet-hook.py") }
            if wired {
                checks.append(HookCheck(
                    title: "Hooks wired into settings.json", status: .ok,
                    detail: "\(commands.filter { $0.contains("pet-hook.py") }.count) hook entries found"
                ))
            } else {
                checks.append(HookCheck(
                    title: "No ClaudePet hooks in settings.json", status: .missing,
                    detail: "Run setup to add them"
                ))
            }
        } else {
            checks.append(HookCheck(
                title: "~/.claude/settings.json not found or unreadable", status: .missing,
                detail: "Run setup to create it"
            ))
        }

        let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/pet/sessions", isDirectory: true)
        if FileManager.default.isWritableFile(atPath: sessionsDir.path) {
            checks.append(HookCheck(title: "Session directory writable", status: .ok, detail: sessionsDir.path))
        } else {
            checks.append(HookCheck(
                title: "Session directory not writable", status: .missing,
                detail: sessionsDir.path
            ))
        }

        return checks
    }

    private static func allCommands(in hooks: [String: Any]) -> [String] {
        var commands: [String] = []
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                guard let entries = group["hooks"] as? [[String: Any]] else { continue }
                for entry in entries {
                    if let command = entry["command"] as? String { commands.append(command) }
                }
            }
        }
        return commands
    }
}
