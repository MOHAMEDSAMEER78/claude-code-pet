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
    static let installedStatusLineURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/pet/bin/pet-statusline.py")
    private static let originalStatusLineConfigURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/pet/original-statusline.json")
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
            // Strip any ClaudePet entries from a previous install/repair
            // before appending the fresh set - otherwise running this twice
            // (first-run offer, then a manual "Repair Hooks" click) leaves
            // TWO copies of the same hook wired in, which fire concurrently
            // on every event and race on writing the same session file.
            let existingGroups = (hooks[event] as? [Any] ?? []).filter { !isClaudePetGroup($0) }
            let newGroups = groups as? [Any] ?? []
            hooks[event] = existingGroups + newGroups
        }
        settings["hooks"] = hooks

        do {
            let output = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: settingsURL)
        } catch {
            throw InstallError.settingsUnwritable(error)
        }
    }

    /// `statusLine` is a single-slot Claude Code setting - it's the only
    /// place the 5-hour/7-day rate-limit usage percentages are exposed
    /// (pet-hook.py's existing hooks never see them), but claiming it is a
    /// bigger behavioral change than adding a hook matcher group, since it
    /// controls what the user's terminal actually renders. So this is a
    /// separate, explicitly opt-in step, not folded into `install()`.
    ///
    /// Whatever `statusLine` command was already configured (if any) is
    /// saved to `original-statusline.json` so the installed wrapper can
    /// chain through to it - the user's own status line output is meant to
    /// be completely unaffected, just with ClaudePet also snapshotting the
    /// usage fields it cares about on the side.
    static func installStatusLineWrapper() throws {
        guard let scriptData = Bundle.main.url(forResource: "pet-statusline", withExtension: "py")
            .flatMap({ try? Data(contentsOf: $0) })
        else { throw InstallError.bundleResourceMissing("pet-statusline.py") }

        try FileManager.default.createDirectory(
            at: installedStatusLineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try scriptData.write(to: installedStatusLineURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedStatusLineURL.path)

        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            guard let existingData = try? Data(contentsOf: settingsURL),
                  let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any]
            else { throw InstallError.settingsUnreadable }
            settings = existing
            let backupURL = settingsURL.appendingPathExtension("bak")
            try? existingData.write(to: backupURL)
        }

        let currentStatusLine = settings["statusLine"] as? [String: Any]
        let alreadyOurs = (currentStatusLine?["command"] as? String) == installedStatusLineURL.path
        if !alreadyOurs {
            // Only overwrite the saved "original" once - re-running this
            // (e.g. a later Repair) must not accidentally save ClaudePet's
            // own wrapper as the thing to chain to.
            let originalData: Data
            if let currentStatusLine {
                originalData = try JSONSerialization.data(withJSONObject: currentStatusLine)
            } else {
                originalData = "null".data(using: .utf8)!
            }
            try? originalData.write(to: originalStatusLineConfigURL)
        }

        settings["statusLine"] = ["type": "command", "command": installedStatusLineURL.path]

        do {
            let output = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: settingsURL)
        } catch {
            throw InstallError.settingsUnwritable(error)
        }
    }

    /// Restores whatever `statusLine` command (if any) was registered
    /// before `installStatusLineWrapper()` claimed the slot.
    static func uninstallStatusLineWrapper() throws {
        guard let existingData = try? Data(contentsOf: settingsURL),
              var settings = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any]
        else { throw InstallError.settingsUnreadable }

        if let originalData = try? Data(contentsOf: originalStatusLineConfigURL),
           let original = try? JSONSerialization.jsonObject(with: originalData) {
            if original is NSNull {
                settings.removeValue(forKey: "statusLine")
            } else {
                settings["statusLine"] = original
            }
        } else {
            settings.removeValue(forKey: "statusLine")
        }

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

    /// Same idea as `diagnose()`, but for the opt-in statusLine wrapper -
    /// kept separate since, unlike the core hooks, this is an optional
    /// feature most users won't have (or want) turned on.
    static func diagnoseStatusLine() -> [HookCheck] {
        var checks: [HookCheck] = []

        let scriptInstalled = FileManager.default.fileExists(atPath: installedStatusLineURL.path)
        let scriptExecutable = FileManager.default.isExecutableFile(atPath: installedStatusLineURL.path)
        if scriptInstalled && scriptExecutable {
            checks.append(HookCheck(title: "Usage-tracking script installed", status: .ok, detail: installedStatusLineURL.path))
        } else {
            checks.append(HookCheck(
                title: "Usage tracking not enabled", status: .missing,
                detail: "Enable it to see 5h/7-day quota in Session Stats"
            ))
            return checks
        }

        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let statusLine = json["statusLine"] as? [String: Any],
           (statusLine["command"] as? String) == installedStatusLineURL.path {
            checks.append(HookCheck(title: "statusLine wired to ClaudePet", status: .ok, detail: "Chains through to your prior statusLine, if any"))
        } else {
            checks.append(HookCheck(
                title: "statusLine not pointed at ClaudePet", status: .warning,
                detail: "Something else has since taken over the statusLine setting"
            ))
        }

        let usageFileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/pet/usage.json")
        if let data = try? Data(contentsOf: usageFileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let updatedAt = json["updatedAt"] as? TimeInterval {
            let age = Date().timeIntervalSince1970 - updatedAt
            if age < 3600 {
                checks.append(HookCheck(title: "Usage data is fresh", status: .ok, detail: "Last updated \(Int(age / 60))m ago"))
            } else {
                checks.append(HookCheck(title: "Usage data is stale", status: .warning, detail: "Last updated over an hour ago - start a Claude Code turn to refresh"))
            }
        } else {
            checks.append(HookCheck(
                title: "No usage data yet", status: .warning,
                detail: "Send a prompt in any Claude Code session to populate it"
            ))
        }

        return checks
    }

    /// True if a hook-config "group" (one matcher's `{matcher, hooks}` entry)
    /// contains a `pet-hook.py` command - whether pointing at the old
    /// checkout-relative placeholder or the installed path, so re-running
    /// install() cleans up entries from either era.
    private static func isClaudePetGroup(_ group: Any) -> Bool {
        guard let group = group as? [String: Any], let entries = group["hooks"] as? [[String: Any]] else { return false }
        return entries.contains { ($0["command"] as? String)?.contains("pet-hook.py") ?? false }
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
