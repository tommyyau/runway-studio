import XCTest
@testable import RunwayStudioTools

final class StudioToolsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func report(stale: Bool = false, reset: String? = nil, cards: Int = 1) -> Report {
        let entries = (0..<cards).map { index in
            Card(providerID: "codex@\(index)", displayName: "Codex", fetchedAt: stamp(now), stale: stale,
                 meters: [Meter(label: "Session", used: 1, limit: 10, resetsAt: reset)], localUsage: nil,
                 liveMeters: [Meter(label: "Session", used: 1, limit: 10, resetsAt: reset)])
        }
        return Report(connected: true, source: "runway_snapshot_cache", observedAt: stamp(now), cards: entries, message: nil)
    }
    func testWaitRequiresFreshUnambiguousPositiveAndUnexpiredReading() {
        XCTAssertTrue(allowanceAvailable(report(), provider: "codex", metric: "Session", now: now))
        XCTAssertFalse(allowanceAvailable(report(stale: true), provider: "codex", metric: "Session", now: now))
        XCTAssertFalse(allowanceAvailable(report(reset: stamp(now)), provider: "codex", metric: "Session", now: now))
        XCTAssertFalse(allowanceAvailable(report(reset: "invalid"), provider: "codex", metric: "Session", now: now))
        XCTAssertFalse(allowanceAvailable(report(cards: 2), provider: "codex", metric: "Session", now: now))
        XCTAssertTrue(allowanceAvailable(report(cards: 2), provider: "codex@1", metric: "Session", now: now))
        XCTAssertNil(Meter(label: "Session", used: nil, limit: 10, resetsAt: nil).remainingPercent)
    }
    func testMCPNegotiationAndProtocolErrors() throws {
        var server = MCPServer()
        func object(_ data: Data?) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
        }
        var response = try object(server.handle(Data("{".utf8), report: report()))
        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? Int, -32700)
        response = try object(server.handle(Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8), report: report()))
        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? Int, -32002)
        response = try object(server.handle(Data(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"unknown","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#.utf8), report: report()))
        XCTAssertEqual((response["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNil(server.handle(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8), report: report()))
        response = try object(server.handle(Data(#"{"jsonrpc":"2.0","id":3,"method":"missing"}"#.utf8), report: report()))
        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? Int, -32601)
        response = try object(server.handle(Data(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"limits","arguments":{"provider":"codex"}}}"#.utf8), report: report(cards: 2)))
        XCTAssertEqual((response["result"] as? [String: Any])?["isError"] as? Bool, true)
    }
    func testReaderDecodesLiveAndCacheAndHandlesMissingData() async throws {
        let snapshot: [String: Any] = ["providerID": "codex@1", "displayName": "Codex", "refreshedAt": stamp(now),
            "lines": [["type": "progress", "label": "Session", "used": 1, "limit": 10]],
            "usageHistory": ["series": ["daily": [["date": "2027-01-15", "totalTokens": 42, "costUSD": 1.0], ["date": "2027-01-16", "totalTokens": 10]]], "unknownModelsByDay": ["2027-01-15": ["unpriced"]]]]
        let cache = try JSONSerialization.data(withJSONObject: ["snapshots": ["codex@1": snapshot], "producedByIdentityKeys": [:]])
        let plist = try PropertyListSerialization.data(fromPropertyList: ["runway.providerSnapshots.v9": cache], format: .binary, options: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try plist.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let liveStamp = stamp(now).replacingOccurrences(of: "Z", with: ".123Z")
        let live = try JSONSerialization.data(withJSONObject: ["providers": ["codex@1": ["fetchedAt": liveStamp, "stale": false,
            "resources": ["session": ["kind": "consumption", "used": 8, "limit": 10]]]], "errors": []])
        let reader = StudioReader(cacheURL: url, studioURL: url.appendingPathExtension("absent-studio"), fetch: { live })
        let result = await reader.read(now: now)
        XCTAssertTrue(allowanceAvailable(result, provider: "codex@1", metric: "Session", now: now))
        XCTAssertEqual(result.cards.first?.localUsage?.first?.totalTokens, 42)
        XCTAssertEqual(result.cards.first?.meters.first(where: { $0.label == "Session" })?.used, 8)
        XCTAssertEqual(result.cards.first?.meters.first(where: { $0.label == "Session" })?.source, "live")
        XCTAssertEqual(result.cards.first?.localUsage?.map(\.costsIncomplete), [true, true])
        let offline = await StudioReader(cacheURL: url, studioURL: url.appendingPathExtension("absent-studio"), fetch: { throw URLError(.notConnectedToInternet) }).read(now: now)
        XCTAssertFalse(offline.connected)
        XCTAssertFalse(allowanceAvailable(offline, provider: "codex@1", metric: "Session", now: now))
        let missing = await StudioReader(cacheURL: url.appendingPathExtension("missing"), studioURL: url.appendingPathExtension("absent-studio"), fetch: { live }).read(now: now)
        XCTAssertEqual(missing.source, "unavailable")
        XCTAssertTrue(missing.cards.isEmpty)
    }

    func testStudioFileEnablesToolsWithoutRunwayAndExposesNextAttempt() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let payload: [String: Any] = [
            "connected": true, "observedAt": stamp(now), "errors": [],
            "nextAttempts": ["claude": stamp(now.addingTimeInterval(120))],
            "providers": ["claude": ["displayName": "Claude", "fetchedAt": stamp(now), "stale": false,
                "resources": ["session": ["kind": "consumption", "used": 4, "limit": 10],
                              "fable": ["kind": "consumption", "used": 2, "limit": 10]]]]
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        let reader = StudioReader(cacheURL: url.appendingPathExtension("missing"), studioURL: url,
                                  fetch: { throw URLError(.notConnectedToInternet) })
        let report = await reader.read(now: now)
        XCTAssertEqual(report.source, "studio_state")
        XCTAssertTrue(allowanceAvailable(report, provider: "claude", metric: "Session", now: now))
        XCTAssertEqual(report.cards.first?.meters.first(where: { $0.label == "Session" })?.source, "studio")
        XCTAssertEqual(report.cards.first?.meters.first(where: { $0.label == "Fable" })?.used, 2)
        XCTAssertTrue(allowanceAvailable(report, provider: "claude", metric: "Fable", now: now))
        XCTAssertEqual(report.nextAttempts["claude"], stamp(now.addingTimeInterval(120)))
        XCTAssertNil(report.cards.first?.localUsage)
    }

    func testStudioFileFailsClosedWhenMalformedOrHeartbeatExpired() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = Data(#"{"providers":{"claude":{"stale":false}}}"#.utf8)
        let reader = StudioReader(cacheURL: url.appendingPathExtension("missing"), studioURL: url, fetch: { legacy })
        try Data("invalid".utf8).write(to: url)
        let malformed = await reader.read(now: now)
        XCTAssertFalse(malformed.connected)
        XCTAssertEqual(malformed.source, "studio_state_unavailable")
        let expired: [String: Any] = ["connected": true, "observedAt": stamp(now.addingTimeInterval(-91)),
                                      "providers": [:], "errors": [], "nextAttempts": [:]]
        try JSONSerialization.data(withJSONObject: expired).write(to: url)
        let result = await reader.read(now: now)
        XCTAssertFalse(result.connected)
        XCTAssertEqual(result.source, "studio_state_unavailable")
        XCTAssertTrue(result.cards.isEmpty)
    }

    func testStudioProviderFreshnessAndErrorsGateWait() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider: [String: Any] = ["displayName": "Claude", "fetchedAt": stamp(now.addingTimeInterval(-361)),
            "stale": false, "resources": ["session": ["kind": "consumption", "used": 1, "limit": 10]]]
        var state: [String: Any] = ["connected": true, "observedAt": stamp(now), "providers": ["claude": provider],
                                   "errors": [], "nextAttempts": [:]]
        try JSONSerialization.data(withJSONObject: state).write(to: url)
        let reader = StudioReader(cacheURL: url.appendingPathExtension("missing"), studioURL: url,
                                  fetch: { throw URLError(.notConnectedToInternet) })
        let old = await reader.read(now: now)
        XCTAssertFalse(allowanceAvailable(old, provider: "claude", metric: "Session", now: now))
        var fresh = provider; fresh["fetchedAt"] = stamp(now)
        state["providers"] = ["claude": fresh]; state["errors"] = [["providerId": "claude", "message": "failed"]]
        try JSONSerialization.data(withJSONObject: state).write(to: url)
        let failed = await reader.read(now: now)
        XCTAssertFalse(allowanceAvailable(failed, provider: "claude", metric: "Session", now: now))
    }

}
