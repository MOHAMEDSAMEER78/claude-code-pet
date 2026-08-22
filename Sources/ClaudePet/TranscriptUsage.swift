import Foundation
import ClaudePetCore

enum TranscriptUsage {
    struct Totals {
        var inputTokens: Int
        var outputTokens: Int
        var cacheCreationTokens: Int
        var cacheReadTokens: Int
        var estimatedCostUSD: Double
        var model: String?
        var isRoughEstimate: Bool

        var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
    }

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
            estimatedCostUSD: PricingTable.estimatedCostUSD(model: model, input: input, output: output, cacheCreate: cacheCreate, cacheRead: cacheRead),
            model: model,
            isRoughEstimate: !PricingTable.isKnownModel(model)
        )
    }
}
