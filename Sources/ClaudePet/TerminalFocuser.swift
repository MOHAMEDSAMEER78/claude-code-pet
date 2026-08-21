import AppKit

/// Brings the exact terminal tab/window running a Claude Code session to the
/// front, not just "some window of the app." Plain NSRunningApplication
/// .activate() only raises whichever window was last active in that app -
/// wrong tab if you have several. We use the session's tty (captured by
/// pet-hook.py by walking the process tree) to ask Terminal.app/iTerm2,
/// which do expose a per-tab/session tty over AppleScript, to select the
/// matching one. A session running inside tmux gets resolved as a tmux pane
/// instead (its tty never matches a terminal tab's tty directly) and its
/// tmux client switched before raising the terminal window the normal way.
/// VS Code/Cursor don't expose per-tab tty at all, so we do the next best
/// thing there: reuse/open the window for the matching workspace folder.
enum TerminalFocuser {
    static func focus(terminalApp: String?, terminalPid: Int32?, tty: String?, cwd: String?) {
        var focused = false

        if let tty, isPlausibleTTYPath(tty) {
            switch terminalApp {
            case "iTerm2":
                focused = focusITerm2(tty: tty)
            case "Terminal":
                focused = focusTerminalApp(tty: tty)
            default:
                break
            }
            // A session's own tty never directly matches a Terminal/iTerm2
            // tab's tty when it's running inside tmux (tmux allocates its
            // own pty per pane) - the direct match above always misses, so
            // try resolving it as a tmux pane instead before giving up.
            if !focused {
                focused = focusTmux(paneTty: tty, terminalApp: terminalApp)
            }
        }

        if !focused, let cwd, let terminalApp {
            if terminalApp.hasPrefix("Cursor") {
                focused = focusEditorWindow(command: "cursor", cwd: cwd)
            } else if terminalApp == "Code" || terminalApp == "Code Helper" {
                focused = focusEditorWindow(command: "code", cwd: cwd)
            }
        }

        if !focused, let terminalPid {
            NSRunningApplication(processIdentifier: terminalPid)?.activate(options: [])
        }
    }

    /// ps reports ttys as e.g. "/dev/ttys001" - guard against anything odd
    /// before splicing it into an AppleScript string literal.
    private static func isPlausibleTTYPath(_ tty: String) -> Bool {
        tty.hasPrefix("/dev/") && tty.allSatisfy { $0.isLetter || $0.isNumber || $0 == "/" }
    }

    private static func focusITerm2(tty: String) -> Bool {
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if (tty of s) is "\(tty)" then
                            tell w to select
                            select t
                            select s
                            activate
                            return "found"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "not found"
        """
        return runAppleScript(script) == "found"
    }

    private static func focusTerminalApp(tty: String) -> Bool {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if (tty of t) is "\(tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return "found"
                    end if
                end repeat
            end repeat
        end tell
        return "not found"
        """
        return runAppleScript(script) == "found"
    }

    /// Best-effort tmux support: a Claude Code session's tty (captured by
    /// pet-hook.py) may actually be a tmux pane's pty rather than a real
    /// terminal tab, if the session is running inside a tmux pane. Resolves
    /// that pane's session, switches the tmux *client* attached to it (not
    /// just server-side state) to that window, then raises the outer
    /// terminal window/tab hosting that client the normal way.
    private static func focusTmux(paneTty: String, terminalApp: String?) -> Bool {
        guard let tmux = resolveBinary("tmux") else { return false }
        guard let target = tmuxPaneTarget(forTty: paneTty, tmux: tmux) else { return false }
        let session = target.split(separator: ":").first.map(String.init) ?? target
        guard let clientTty = tmuxClientTty(forSession: session, tmux: tmux) else { return false }

        _ = runTmux(tmux, ["switch-client", "-c", clientTty, "-t", target])
        _ = runTmux(tmux, ["select-window", "-t", target])

        switch terminalApp {
        case "iTerm2": return focusITerm2(tty: clientTty)
        case "Terminal": return focusTerminalApp(tty: clientTty)
        default:
            // Unknown/unsupported outer terminal app - tmux's own focus did
            // switch, which is real progress even without raising a window.
            return true
        }
    }

    /// tmux reports "pane_tty session:window.pane" per line - find the one
    /// whose pane_tty matches this session's tty and return its target spec.
    private static func tmuxPaneTarget(forTty tty: String, tmux: String) -> String? {
        guard let output = runTmux(tmux, ["list-panes", "-a", "-F", "#{pane_tty} #{session_name}:#{window_index}.#{pane_index}"])
        else { return nil }
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, parts[0] == Substring(tty) else { continue }
            return String(parts[1])
        }
        return nil
    }

    /// The real terminal-emulator tty of whichever client has this tmux
    /// session attached - that's what Terminal.app/iTerm2's own AppleScript
    /// tty-matching needs, not the pane's tty inside tmux.
    private static func tmuxClientTty(forSession session: String, tmux: String) -> String? {
        runTmux(tmux, ["list-clients", "-t", session, "-F", "#{client_tty}"])?
            .split(separator: "\n").first.map(String.init)
    }

    @discardableResult
    private static func runTmux(_ tmux: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmux)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (output?.isEmpty == false) ? output : nil
        } catch {
            return nil
        }
    }

    /// `code -r <folder>` / `cursor -r <folder>` reuses (or opens) the window
    /// for that workspace - not the exact integrated-terminal panel, but a
    /// real improvement over "whichever VS Code window happened to be frontmost."
    ///
    /// ClaudePet.app is launched by LaunchServices (Finder/`open`), not a
    /// shell, so it inherits launchd's minimal PATH
    /// (/usr/bin:/bin:/usr/sbin:/sbin) - it never sees /usr/local/bin or
    /// /opt/homebrew/bin, which is where these CLI shims actually live, so
    /// `env <command>` silently fails to find them. Search the well-known
    /// install locations directly instead of trusting PATH.
    private static func focusEditorWindow(command: String, cwd: String) -> Bool {
        guard let binary = resolveBinary(command) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-r", cwd]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func resolveBinary(_ command: String) -> String? {
        let candidates = [
            "/usr/local/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            NSHomeDirectory() + "/.local/bin/\(command)",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        // Fall back to whatever the invoking shell's PATH resolves, in case
        // it's installed somewhere nonstandard.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = [command]
        let pipe = Pipe()
        which.standardOutput = pipe
        do {
            try which.run()
            which.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (output?.isEmpty == false) ? output : nil
        } catch {
            return nil
        }
    }

    private static func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("ClaudePet: AppleScript focus failed: \(error)")
            return nil
        }
        return result.stringValue
    }
}
