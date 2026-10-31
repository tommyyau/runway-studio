import XCTest
@testable import RunwayStudioKit

final class StudioMenuSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }
    private let now = ISO8601DateFormatter().date(from: "2026-10-26T08:00:00Z")!
    private func card(_ id: String = "claude", cost: Double? = 12) -> StudioSnapshot {
        StudioSnapshot(providerID: id, displayName: id, refreshedAt: now, lines: [],
            usageHistory: StudioUsageHistory(series: .init(daily: [
                StudioDay(date: "2026-10-26", totalTokens: 100, costUSD: cost),
                StudioDay(date: "2026-10-25", totalTokens: 200, costUSD: 20)])))
    }

    func testCalendarRangesIncludeYesterdayAcrossDSTAndThirtyDates() {
        XCTAssertEqual(StudioSummaryRange.yesterday.keys(now: now, calendar: calendar), ["2026-10-25"])
        XCTAssertEqual(StudioSummaryRange.month.keys(now: now, calendar: calendar).count, 30)
        let result = StudioSummaryValue.build(snapshots: [card()], range: .yesterday, now: now, calendar: calendar)
        XCTAssertEqual(result.first?.cost, 20)
        XCTAssertEqual(result.first?.tokens, 200)
    }

    func testSharedLocalHistoryIsCountedOncePerProvider() {
        let result = StudioSummaryValue.build(snapshots: [card("claude@work", cost: 90), card(), card("codex")],
            range: .today, now: now, calendar: calendar)
        XCTAssertEqual(result.map(\.id), ["claude", "codex"])
        XCTAssertEqual(result.compactMap(\.cost).reduce(0, +), 24)
    }

    func testUnpricedOrMissingHistoryNeverBecomesZeroDollarEstimate() {
        var missing = card(cost: nil)
        var result = StudioSummaryValue.build(snapshots: [missing], range: .today, now: now, calendar: calendar)[0]
        XCTAssertNil(result.cost)
        XCTAssertTrue(result.incomplete)
        missing.usageHistory = nil
        result = StudioSummaryValue.build(snapshots: [missing], range: .today, now: now, calendar: calendar)[0]
        XCTAssertNil(result.cost)
        XCTAssertNil(result.tokens)
    }

    func testUnknownModelsMarkKnownSubtotalIncomplete() {
        var snapshot = card()
        snapshot.usageHistory?.unknownModelsByDay = ["2026-10-26": ["unknown"]]
        let result = StudioSummaryValue.build(snapshots: [snapshot], range: .today, now: now, calendar: calendar)[0]
        XCTAssertEqual(result.cost, 12)
        XCTAssertTrue(result.incomplete)
    }
}
