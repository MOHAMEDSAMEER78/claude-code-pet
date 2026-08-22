import Foundation

public struct PermissionRequest: Codable, Identifiable {
    public var id: String { requestId }
    public var requestId: String
    public var sessionId: String
    public var tool: String?
    public var summary: String?
    public var cwd: String?
    public var ts: TimeInterval

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case sessionId = "session_id"
        case tool, summary, cwd, ts
    }

    public init(requestId: String, sessionId: String, tool: String?, summary: String?, cwd: String?, ts: TimeInterval) {
        self.requestId = requestId
        self.sessionId = sessionId
        self.tool = tool
        self.summary = summary
        self.cwd = cwd
        self.ts = ts
    }
}
