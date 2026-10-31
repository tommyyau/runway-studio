import Foundation
import CoreFoundation

struct MCPServer {
    var initialized = false
    let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    mutating func handle(_ data: Data, report: Report) -> Data? {
        func encode(_ object: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]) }
        func error(_ id: Any, _ code: Int, _ message: String) -> Data? {
            encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return error(NSNull(), -32700, "Parse error")
        }
        guard let request = object as? [String: Any] else { return error(NSNull(), -32600, "Invalid Request") }
        let id = request["id"]
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String,
              id == nil || id is String || (id is NSNumber && CFGetTypeID(id as CFTypeRef) != CFBooleanGetTypeID()) || id is NSNull else {
            return error(NSNull(), -32600, "Invalid Request")
        }
        // Notifications never receive a response.
        guard let id else { return nil }
        func result(_ value: [String: Any]) -> Data? { encode(["jsonrpc": "2.0", "id": id, "result": value]) }
        if method == "initialize" {
            guard let params = request["params"] as? [String: Any], let requested = params["protocolVersion"] as? String, !requested.isEmpty,
                  params["capabilities"] is [String: Any], let client = params["clientInfo"] as? [String: Any],
                  client["name"] is String, client["version"] is String else {
                return error(id, -32602, "Invalid params")
            }
            initialized = true
            return result(["protocolVersion": supportedVersions.contains(requested) ? requested : supportedVersions[0],
                           "capabilities": ["tools": [:]], "serverInfo": ["name": "runway-studio", "version": "1.0.0"]])
        }
        if method == "ping" { return result([:]) }
        guard initialized else { return error(id, -32002, "Server not initialized") }
        if method == "tools/list" {
            let schema: [String: Any] = ["type": "object", "properties": ["provider": ["type": "string", "description": "Exact card ID, or an unambiguous provider family"]], "additionalProperties": false]
            let tools: [[String: Any]] = [
                ["name": "status", "description": "Read Runway connection and snapshot freshness", "inputSchema": schema, "annotations": ["readOnlyHint": true]],
                ["name": "limits", "description": "Read allowance meters and their source timestamps", "inputSchema": schema, "annotations": ["readOnlyHint": true]],
                ["name": "local_usage", "description": "Read machine-local daily tokens and estimated API value, not subscription billing; history spans accounts, so do not sum account cards", "inputSchema": schema, "annotations": ["readOnlyHint": true]]
            ]
            return result(["tools": tools])
        }
        if method == "tools/call" {
            guard let params = request["params"] as? [String: Any], let name = params["name"] as? String,
                  ["status", "limits", "local_usage"].contains(name) else { return error(id, -32602, "Unknown tool or invalid params") }
            guard let args = (params["arguments"] ?? [:]) as? [String: Any], args.keys.allSatisfy({ $0 == "provider" }),
                  args["provider"] == nil || args["provider"] is String else { return error(id, -32602, "Invalid tool arguments") }
            var selected = report.cards
            if let provider = args["provider"] as? String {
                guard let card = matchingCard(report, provider: provider) else {
                    return result(["content": [["type": "text", "text": "Provider not found or ambiguous; specify an exact card ID."]], "isError": true])
                }
                selected = [card]
            }
            let entries: [[String: Any]] = selected.map { card in
                var item: [String: Any] = ["providerID": card.providerID, "displayName": card.displayName, "fetchedAt": card.fetchedAt, "stale": card.stale, "accountScope": card.accountScope]
                if let liveFetchedAt = card.liveFetchedAt { item["liveFetchedAt"] = liveFetchedAt }
                if name == "limits", let data = try? JSONEncoder().encode(card.meters), let value = try? JSONSerialization.jsonObject(with: data) { item["meters"] = value }
                if name == "local_usage" { item["scope"] = "machine-local, across accounts; do not sum account cards"; item["costMeaning"] = "estimated API value, not subscription billing" }
                if name == "local_usage", let days = card.localUsage, let data = try? JSONEncoder().encode(days), let value = try? JSONSerialization.jsonObject(with: data) { item["daily"] = value }
                return item
            }
            var payload: [String: Any] = ["connected": report.connected, "source": report.source, "observedAt": report.observedAt, "cards": entries]
            if let message = report.message { payload["message"] = message }
            if !report.nextAttempts.isEmpty { payload["nextAttempts"] = report.nextAttempts }
            let payloadData = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
            return result(["content": [["type": "text", "text": String(decoding: payloadData, as: UTF8.self)]]])
        }
        return error(id, -32601, "Method not found")
    }
}
