import Foundation

/// A pending permission decision, written by pet-hook.py (in `await-permission`
/// mode) when Claude Code's `PermissionRequest` hook fires. The hook process
/// blocks polling for a matching response file; the app shows an Allow/Deny
/// bubble and writes the response when the user clicks.
struct PermissionRequest: Codable, Identifiable {
    var id: String { requestId }
    var requestId: String
    var sessionId: String
    var tool: String?
    var summary: String?
    var cwd: String?
    var ts: TimeInterval

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case sessionId = "session_id"
        case tool, summary, cwd, ts
    }
}
