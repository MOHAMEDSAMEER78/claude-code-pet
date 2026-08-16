import AppKit

/// Brings the exact terminal tab/window running a Claude Code session to the
/// front, not just "some window of the app." Plain NSRunningApplication
/// .activate() only raises whichever window was last active in that app -
/// wrong tab if you have several. We use the session's tty (captured by
/// pet-hook.py by walking the process tree) to ask Terminal.app/iTerm2,
/// which do expose a per-tab/session tty over AppleScript, to select the
/// matching one. VS Code/Cursor don't expose that, so we do the next best
/// thing: reuse/open the window for the matching workspace folder.
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

    /// `code -r <folder>` / `cursor -r <folder>` reuses (or opens) the window
    /// for that workspace - not the exact integrated-terminal panel, but a
    /// real improvement over "whichever VS Code window happened to be frontmost."
    private static func focusEditorWindow(command: String, cwd: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command, "-r", cwd]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
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
