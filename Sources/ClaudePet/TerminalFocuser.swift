import AppKit

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
            return true
        }
    }

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
