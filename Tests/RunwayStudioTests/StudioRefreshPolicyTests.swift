import XCTest
@testable import RunwayStudioKit

final class StudioRefreshPolicyTests: XCTestCase {
    private func card(_ id: String, wait: Bool = false) -> StudioSnapshot {
        var snapshot = StudioSnapshot(providerID: id, displayName: id, refreshedAt: Date(), lines: [])
        snapshot.warningAction = wait ? "wait" : nil
        snapshot.warning = wait ? "Updates blocked by Anthropic. Retrying in ~now." : nil
        return snapshot
    }
    func testDefaultFamilyIsRequestedOnlyOnceAndHiddenWaitBlocksWholeFamily() {
        let cards = [card("claude"), card("claude@work"), card("codex")]
        let plan = StudioRefreshPlan(visible: cards, allCached: cards)
        XCTAssertEqual(plan.requests, ["claude", "codex"])
        let waiting = StudioRefreshPlan(visible: cards, allCached: cards + [card("claude@hidden", wait: true)])
        XCTAssertEqual(waiting.requests, ["codex"])
        XCTAssertEqual(waiting.waitingFamilies, ["claude"])
    }
    func testNamedOnlyCardsUseExactSelectorsAndExcludeOtherProviders() {
        let cards = [card("codex@work"), card("codex@personal"), card("cursor")]
        XCTAssertEqual(StudioRefreshPlan(visible: cards, allCached: cards).requests, ["codex@personal", "codex@work"])
    }
    func testOldHelperTimestampIsNotReportedAsFreshAndWaitCopyHasNoFrozenCountdown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(StudioRefreshPlan.confirmsNewReading(previous: now.addingTimeInterval(-500), reported: now.addingTimeInterval(-300), started: now))
        XCTAssertFalse(StudioRefreshPlan.confirmsNewReading(previous: now, reported: now, started: now))
        XCTAssertTrue(StudioRefreshPlan.confirmsNewReading(previous: now.addingTimeInterval(-300), reported: now, started: now))
        XCTAssertFalse(card("claude", wait: true).displayWarning!.contains("~now"))
        XCTAssertTrue(card("claude", wait: true).waitsForProvider)
    }

    func testDelayedCacheWriteMustReachReportedTimestampAndRecoveryClearsWait() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = card("codex")
        snapshot.refreshedAt = now.addingTimeInterval(-300)
        XCTAssertFalse(StudioRefreshPlan.cacheHasReportedReadings([snapshot], reported: ["codex": now]))
        snapshot.refreshedAt = now
        XCTAssertTrue(StudioRefreshPlan.cacheHasReportedReadings([snapshot], reported: ["codex": now]))
        XCTAssertTrue(StudioRefreshPlan(visible: [card("claude")], allCached: [card("claude")]).waitingFamilies.isEmpty)
    }
}
