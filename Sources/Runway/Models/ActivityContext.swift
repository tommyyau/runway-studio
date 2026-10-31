import Foundation

/// Log metadata only. Never contains a prompt, response, auth token or account credential.
struct ActivityContext: Codable, Sendable, Equatable {
    var cwd: String?
    var sessionID: String?
    var agentID: String?
    var role: String?
    var name: String?

    static func codex(_ payload: [String: Any]?) -> Self? {
        guard let payload else { return nil }
        let source = payload["source"] as? [String: Any]
        let recordedSubagent: Bool
        switch source?["subagent"] {
        case nil, is NSNull: recordedSubagent = false
        case let text as String: recordedSubagent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: recordedSubagent = true
        }
        let subagent = payload["thread_source"] as? String == "subagent" || recordedSubagent
        let knownMain = payload["thread_source"] as? String == "user" || payload["source"] is String
        return Self(cwd: payload["cwd"] as? String, sessionID: payload["id"] as? String,
                    agentID: subagent ? payload["id"] as? String : nil,
                    role: subagent ? "Subagent" : knownMain ? "Main Session" : nil,
                    name: payload["agent_nickname"] as? String)
    }
}
