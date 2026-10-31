import XCTest
@testable import RunwayStudioKit

final class ActivityReportTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(_ offset: TimeInterval, provider: String = "claude", project: String = "app", path: String = "/a/app",
                       role: String = "Main Session", agent: String = "one", tokens: ActivityTokens = .init(input: 10, cached: 80, output: 5)) -> ActivityEvent {
        ActivityEvent(provider: provider, timestamp: start.addingTimeInterval(offset), project: project, projectPath: path,
            session: agent, agentID: agent, agentRole: role, agentName: agent, model: "test", tokens: tokens)
    }
    private func report(_ events: [ActivityEvent], grouping: ActivityGrouping = .project, newOnly: Bool = false,
                        selection: ClosedRange<Date>? = nil) -> ActivityReport {
        ActivityReport.build(events: events, provider: "claude", interval: DateInterval(start: start, duration: 10800),
                             resolution: .hourly, grouping: grouping, selection: selection, newOnly: newOnly)
    }

    func testProviderAndWindowBoundariesAndTotalsAgree() {
        let result = report([event(-1), event(0), event(1, provider: "codex"), event(10799), event(10800)])
        XCTAssertEqual(result.totals.total, 190)
        XCTAssertEqual(result.buckets.reduce(0) { $0 + $1.tokens.total }, result.totals.total)
        XCTAssertEqual(result.groups.reduce(0) { $0 + $1.tokens.total }, result.totals.total)
    }

    func testSameNamedProjectsInDifferentFoldersStaySeparate() {
        XCTAssertEqual(report([event(0), event(1, path: "/b/app")]).groups.count, 2)
    }

    func testMainAndSubagentsRetainIndividualBreakdowns() {
        let result = report([event(0), event(1, role: "Subagent", agent: "child"), event(2, role: "Subagent", agent: "second")], grouping: .agent)
        XCTAssertEqual(result.groups.count, 2)
        XCTAssertEqual(result.groups.first { $0.title == "Subagent" }?.children.count, 2)
        XCTAssertEqual(result.groups.first { $0.title == "Subagent" }?.tokens.total, 190)
    }

    func testNewOnlyExcludesCacheWithoutChangingRecordedTotals() {
        let result = report([event(0)], newOnly: true)
        XCTAssertEqual(result.totals.newOnly, 15)
        XCTAssertEqual(result.totals.total, 95)
        XCTAssertEqual(result.groups.first?.tokens.newOnly, 15)
    }

    func testSelectionUsesExactBoundariesForTotalsAndBreakdown() {
        let hour = Calendar.current.dateInterval(of: .hour, for: start)!
        let chosen = start.addingTimeInterval(10)...start.addingTimeInterval(20)
        let result = report([event(9, path: "/before/app"), event(10), event(20),
                             event(21, path: "/after/app"),
                             event(hour.end.timeIntervalSince(start) + 1, path: "/other/app")], selection: chosen)
        XCTAssertEqual(result.totals.total, 190) // Both selected endpoints are inclusive.
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups.first?.tokens.total, 190)
        XCTAssertEqual(result.buckets.count, 2) // Unselected chart bars remain available but dimmed.
        XCTAssertEqual(result.selectedInterval.start, chosen.lowerBound)
    }

    func testSelectionClampsToVisibleWindow() {
        let chosen = start.addingTimeInterval(-60)...start.addingTimeInterval(60)
        let result = report([event(0), event(60), event(61)], selection: chosen)
        XCTAssertEqual(result.selectedInterval.start, start)
        XCTAssertEqual(result.totals.total, 190)
        XCTAssertEqual(result.groups.first?.tokens.total, 190)
    }

    func testLast24HoursIsRollingRatherThanStartOfDay() {
        let range = ActivityReport.interval(days: 1, now: start)
        XCTAssertEqual(range.duration, 86400)
        XCTAssertEqual(range.end, start)
    }

    func testRepeatedDSTHoursStaySeparate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let first = ISO8601DateFormatter().date(from: "2026-10-25T00:30:00Z")!
        let second = first.addingTimeInterval(3600)
        var a = event(0); a.timestamp = first
        var b = event(0); b.timestamp = second
        let result = ActivityReport.build(events: [a, b], provider: "claude",
            interval: DateInterval(start: first.addingTimeInterval(-1800), duration: 3 * 3600), resolution: .hourly, grouping: .project, calendar: calendar)
        XCTAssertEqual(result.buckets.count, 2)
        XCTAssertEqual(result.buckets[1].start.timeIntervalSince(result.buckets[0].start), 3600)
    }

    func testWorktreeAndSubfoldersResolveToMainRepository() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("repo", isDirectory: true)
        let tree = root.appendingPathComponent("feature", isDirectory: true)
        let metadata = main.appendingPathComponent(".git/worktrees/feature", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tree.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "gitdir: ../repo/.git/worktrees/feature\n".write(to: tree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try "../..\n".write(to: metadata.appendingPathComponent("commondir"), atomically: true, encoding: .utf8)
        var resolver = ActivityProjectResolver()
        let resolved = resolver.resolve(tree.appendingPathComponent("src").path)
        XCTAssertEqual(resolved.path, main.resolvingSymlinksInPath().path)
        XCTAssertEqual(resolved.name, "repo")
    }

    func testMissingProjectMetadataRemainsUnknown() {
        var resolver = ActivityProjectResolver()
        XCTAssertEqual(resolver.resolve(nil).name, "Unknown Project")
    }

    func testWorkspaceProjectGroupsNestedNonGitOutputFolders() {
        var resolver = ActivityProjectResolver()
        resolver.workspaceRoots = [URL(fileURLWithPath: "/example-workspaces", isDirectory: true)]
        XCTAssertEqual(resolver.resolve("/example-workspaces/content/render/frames").path, "/example-workspaces/content")
    }
}

extension ActivityReportTests {
    func testFiveMinuteBucketsAndPreciseSelection() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [event(10), event(60), event(310)]
        let result = ActivityReport.build(events: events, provider: "claude",
            interval: DateInterval(start: base, duration: 600), resolution: .fiveMinutes,
            grouping: .project, selection: base.addingTimeInterval(30)...base.addingTimeInterval(80), calendar: calendar)
        XCTAssertEqual(result.buckets.count, 2)
        XCTAssertEqual(result.buckets[0].end.timeIntervalSince(result.buckets[0].start), 300)
        XCTAssertEqual(result.totals.total, 95)
    }

    func testSourceBreakdownUsesRecordedSource() {
        var a = event(0); a.source = "Claude Code"
        var b = event(1); b.source = "Claude Cowork"
        let result = report([a, b], grouping: .source)
        XCTAssertEqual(Set(result.groups.map(\.title)), ["Claude Code", "Claude Cowork"])
        XCTAssertEqual(result.groups.reduce(0) { $0 + $1.tokens.total }, result.totals.total)
    }
}
