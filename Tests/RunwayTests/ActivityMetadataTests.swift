import XCTest
@testable import Runway

final class ActivityMetadataTests: XCTestCase {
    func testCodexCachedAndReasoningTokensAreNotAddedTwice() {
        let event = CodexLogUsageScanner.Event(timestamp: Date(), model: "unpriced-test-model",
            input: 100, cached: 80, output: 20, reasoning: 15, total: 120)
        let activity = LocalActivityEvent(codex: event)
        XCTAssertEqual(activity.input, 20)
        XCTAssertEqual(activity.cached, 80)
        XCTAssertEqual(activity.output, 20)
        XCTAssertEqual(activity.unclassified, 0)
        XCTAssertEqual(activity.input + activity.cached + activity.output, 120)
        XCTAssertEqual(activity.model, "unpriced-test-model")
    }

    func testClaudeCacheWritesAreNewInputAndCacheReadsStaySeparate() {
        let entry = ClaudeLogUsageScanner.Entry(timestamp: Date(),
            tokens: TokenBreakdown(input: 10, cacheWrite5m: 20, cacheWrite1h: 30, cacheRead: 40, output: 5))
        let activity = LocalActivityEvent(claude: entry)
        XCTAssertEqual(activity.input, 60)
        XCTAssertEqual(activity.cached, 40)
        XCTAssertEqual(activity.output, 5)
        XCTAssertEqual(activity.input + activity.cached + activity.output, entry.tokens.totalTokens)
    }

    func testNullSubagentIsNotAnAgentAndForkRemainsMain() {
        XCTAssertNil(ActivityContext.codex(["source": ["subagent": NSNull()]])?.role)
        XCTAssertEqual(ActivityContext.codex(["source": "vscode", "forked_from_id": "parent"])?.role, "Main Session")
    }

    func testClaudeMetadataSurvivesSidechainDedup() throws {
        let line = """
        {"type":"assistant","timestamp":"2026-10-31T10:00:00Z","cwd":"/repo","sessionId":"parent","agentId":"child","isSidechain":true,"requestId":"r","message":{"id":"m","model":"claude-test","usage":{"input_tokens":10,"output_tokens":2,"cache_read_input_tokens":80}}}
        """
        let entries = ClaudeLogUsageScanner.parseFile(Data(line.utf8))
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.activity?.cwd, "/repo")
        XCTAssertEqual(entry.activity?.role, "Subagent")
        XCTAssertEqual(entry.activity?.agentID, "child")
        XCTAssertEqual(ClaudeLogUsageScanner.dedup(entries + entries).count, 1)
    }

    func testCodexMetadataSurvivesTailResumeAndIgnoresReplayedParentMetadata() throws {
        var state = CodexLogUsageScanner.ParseState()
        let header = """
        {"type":"session_meta","timestamp":"2026-10-31T10:00:00Z","payload":{"id":"child","cwd":"/repo","thread_source":"subagent","parent_thread_id":"parent","agent_nickname":"Scout"}}
        {"type":"session_meta","timestamp":"2026-10-31T10:00:00Z","payload":{"id":"parent","cwd":"/wrong","source":"cli"}}
        {"type":"event_msg","timestamp":"2026-10-31T10:00:00Z","payload":{"type":"task_started","started_at":1793440800}}
        """
        _ = CodexLogUsageScanner.parseChunk(Data(header.utf8), state: &state)
        let saved = try JSONEncoder().encode(state)
        var resumed = try JSONDecoder().decode(CodexLogUsageScanner.ParseState.self, from: saved)
        let usage = """
        {"type":"event_msg","timestamp":"2026-10-31T10:01:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":5,"total_tokens":105},"total_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":5,"total_tokens":105}}}}
        """
        let events = CodexLogUsageScanner.parseChunk(Data(usage.utf8), state: &resumed)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.activity?.cwd, "/repo")
        XCTAssertEqual(event.activity?.sessionID, "child")
        XCTAssertEqual(event.activity?.name, "Scout")
        XCTAssertEqual(event.activity?.role, "Subagent")
        XCTAssertEqual(CodexLogUsageScanner.deduplicatedEvents(events + events).count, 1)
    }
    func testClaudeSourcePathsRemainDistinctAfterScanning() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let code = home.appendingPathComponent(".claude")
        let cowork = home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions/group/sub/local_1/.claude")
        let unknown = home.appendingPathComponent("custom")
        for (root, id) in [(code, "code"), (cowork, "cowork"), (unknown, "unknown")] {
            let project = root.appendingPathComponent("projects/project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let line = """
            {"type":"assistant","timestamp":"2026-10-31T10:00:00Z","requestId":"\(id)","message":{"id":"\(id)","model":"test","usage":{"input_tokens":10,"output_tokens":2}}}

            """
            try line.write(to: project.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        }
        let scanner = ClaudeLogUsageScanner(homeDirectory: { home },
            incrementalScanner: IncrementalJSONLScanner(logTag: "test"),
            cacheIdentityOverride: "source-fixture", rootsOverride: [code, cowork, unknown])
        let now = ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!
        let scanned = await scanner.scanEvents(now: now)
        let entries = try XCTUnwrap(scanned)
        let byID = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            entry.messageID.map { ($0, entry.source) }
        })
        XCTAssertEqual(byID["code"]!, "Claude Code")
        XCTAssertEqual(byID["cowork"]!, "Claude Cowork")
        XCTAssertEqual(byID["unknown"]!, "Unknown Claude Source")
    }

    func testClaudeSourceClassificationAndConflictingDuplicateRemainUnknown() {
        let home = URL(fileURLWithPath: "/Users/example")
        XCTAssertNil(ClaudeLogUsageScanner.activitySource(path: "/Users/example/.claude-extra/projects/x.jsonl", home: home))
        XCTAssertNil(ClaudeLogUsageScanner.activitySource(path: "/Users/example/custom/projects/x.jsonl", home: home))
        var a = ClaudeLogUsageScanner.Entry(timestamp: Date(), tokens: TokenBreakdown(input: 10), messageID: "m", requestID: "r")
        a.source = "Claude Code"
        var b = a; b.source = "Claude Cowork"
        XCTAssertEqual(ClaudeLogUsageScanner.dedup([a, b]).first?.source, "Unknown Claude Source")
        XCTAssertEqual(LocalActivityEvent(claude: ClaudeLogUsageScanner.Entry(timestamp: Date(), tokens: TokenBreakdown())).source, "Unknown Claude Source")
    }

}
