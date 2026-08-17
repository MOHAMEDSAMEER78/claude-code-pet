import Foundation

/// Reads token usage straight out of Claude Code's own transcript files -
/// not the hook payloads, which don't carry usage data. Claude Code writes
/// a JSONL transcript per session at
/// ~/.claude/projects/<sanitized-cwd>/<session_id>.jsonl, and every
/// assistant message in it carries a `usage` object (input/output/cache
/// tokens, model). This is an undocumented, internal format - not a stable
/// public API - so treat every number here as a best-effort estimate that
/// can break silently if Claude Code changes its transcript layout.
enum TranscriptUsage {
    struct Totals {
        var inputTokens: Int
        var outputTokens: Int
        var cacheCreationTokens: Int
        var cacheReadTokens: Int
        var estimatedCostUSD: Double
        var model: String?

        var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
    }

    /// Rather than reproducing Claude Code's own cwd-sanitization scheme to
    /// find the right project subdirectory, just search every project
    /// directory for a file named `<sessionId>.jsonl` - the session id is
    /// already unique, so this is both simpler and more robust to that
    /// scheme changing.
    static func transcriptURL(forSession sessionId: String) -> URL? {
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil)
        else { return nil }
        for dir in projectDirs {
            let candidate = dir.appendingPathComponent("\(sessionId).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Sums usage across every assistant message in the transcript. Reads
    /// the whole file on each call - only invoked on demand (tray row
    /// appearing, Stats window opening), never on SessionStore's refresh
    /// timer, so an occasional multi-MB transcript is an acceptable cost.
    static func totals(forSession sessionId: String) -> Totals? {
        guard let url = transcriptURL(forSession: sessionId),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        var input = 0, output = 0, cacheCreate = 0, cacheRead = 0
        var model: String?
        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }
            input += usage["input_tokens"] as? Int ?? 0
            output += usage["output_tokens"] as? Int ?? 0
            cacheCreate += usage["cache_creation_input_tokens"] as? Int ?? 0
            cacheRead += usage["cache_read_input_tokens"] as? Int ?? 0
            if let m = message["model"] as? String { model = m }
        }
        guard input + output + cacheCreate + cacheRead > 0 else { return nil }
        return Totals(
            inputTokens: input, outputTokens: output,
            cacheCreationTokens: cacheCreate, cacheReadTokens: cacheRead,
            estimatedCostUSD: estimatedCostUSD(model: model, input: input, output: output, cacheCreate: cacheCreate, cacheRead: cacheRead),
            model: model
        )
    }

    /// Rough per-million-token pricing (standard tier, USD). Hardcoded and
    /// will drift out of date as pricing changes - this is meant to be a
    /// ballpark, not a bill. Unrecognized/future model names fall back to
    /// Sonnet-tier pricing rather than silently reporting $0.
    private static func pricing(for model: String?) -> (input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        let m = (model ?? "").lowercased()
        if m.contains("opus") { return (15, 75, 18.75, 1.5) }
        if m.contains("haiku") { return (0.8, 4, 1, 0.08) }
        return (3, 15, 3.75, 0.3) // sonnet, and unknown/default
    }

    private static func estimatedCostUSD(model: String?, input: Int, output: Int, cacheCreate: Int, cacheRead: Int) -> Double {
        let p = pricing(for: model)
        let million = 1_000_000.0
        return Double(input) * p.input / million
            + Double(output) * p.output / million
            + Double(cacheCreate) * p.cacheWrite / million
            + Double(cacheRead) * p.cacheRead / million
    }
}
