import XCTest
@testable import RunwayStudioKit

final class AlertEngineTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!
    private var preferences: StudioAlertPreferences { var p = StudioAlertPreferences(); p.morning = false; return p }
    private func observation(_ remaining: Double = 80, offset: TimeInterval = 0, account: String = "claude:A",
                             session: Double? = nil) -> StudioAlertObservation {
        StudioAlertObservation(account: account, cardID: "claude", name: "Claude", family: "claude",
            fetchedAt: now.addingTimeInterval(offset), weekly: StudioAlertMeter(remaining: remaining, reset: now.addingTimeInterval(2 * 86400)),
            session: session.map { StudioAlertMeter(remaining: $0, reset: now.addingTimeInterval(7200), duration: 18000) },
            credits: 0, expiries: [], fresh: true)
    }
    private func evaluate(_ engine: inout StudioAlertEngine, _ observation: StudioAlertObservation,
                          preferences p: StudioAlertPreferences? = nil) -> [StudioAlertEvent] {
        engine.evaluate([observation], now: observation.fetchedAt, preferences: p ?? preferences)
    }

    func testInitialReadingDoesNotInventTransition() {
        var engine = StudioAlertEngine()
        XCTAssertTrue(evaluate(&engine, observation(5)).isEmpty)
    }

    func testLowWarningIsDeliveredOncePerWindowAcrossRestart() throws {
        var engine = StudioAlertEngine()
        _ = evaluate(&engine, observation())
        let event = try XCTUnwrap(evaluate(&engine, observation(9, offset: 300)).first)
        XCTAssertEqual(event.kind, .low)
        engine.acknowledge(event, now: now.addingTimeInterval(300))
        engine = try JSONDecoder().decode(StudioAlertEngine.self, from: JSONEncoder().encode(engine))
        XCTAssertTrue(evaluate(&engine, observation(5, offset: 900)).isEmpty)
    }

    func testStaleReadingsNeverCreateAllowanceAlerts() {
        var engine = StudioAlertEngine()
        _ = evaluate(&engine, observation())
        var stale = observation(1, offset: 300); stale.fresh = false
        XCTAssertTrue(evaluate(&engine, stale).isEmpty)
    }

    func testRepeatedTimestampDoesNotCreateTransitions() {
        var engine = StudioAlertEngine()
        _ = evaluate(&engine, observation())
        XCTAssertTrue(evaluate(&engine, observation(1)).isEmpty)
    }

    func testAccountChangeStartsNewBaseline() {
        var engine = StudioAlertEngine()
        _ = evaluate(&engine, observation())
        XCTAssertTrue(evaluate(&engine, observation(1, offset: 300, account: "claude:B")).isEmpty)
        XCTAssertEqual(engine.accounts.count, 2)
    }

    func testConfirmedSessionRecovery() throws {
        var engine = StudioAlertEngine()
        _ = evaluate(&engine, observation(session: 0))
        let event = try XCTUnwrap(evaluate(&engine, observation(offset: 300, session: 70)).first)
        XCTAssertEqual(event.kind, .recovery)
    }

    func testMissingSessionMetricIsNotProofOfRecovery() {
        var engine = StudioAlertEngine()
        _ = evaluate(&engine, observation(session: 0))
        XCTAssertFalse(evaluate(&engine, observation(offset: 300)).contains { $0.kind == .recovery })
    }

    func testEarlyResetAndNewCreditProduceOneNotification() throws {
        var engine = StudioAlertEngine()
        _ = evaluate(&engine, observation(40))
        var next = observation(100, offset: 300)
        next.weekly?.reset = now.addingTimeInterval(7 * 86400); next.credits = 2
        let events = evaluate(&engine, next)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .reset)
        XCTAssertTrue(try XCTUnwrap(events.first).body.contains("2 new reset credits"))
    }

    func testForecastRequiresAtLeastTwelveHoursEarly() {
        var engine = StudioAlertEngine()
        var baseline = observation(60); baseline.weekly?.reset = now.addingTimeInterval(5 * 86400)
        _ = evaluate(&engine, baseline)
        var next = baseline; next.fetchedAt = now.addingTimeInterval(300); next.weekly?.remaining = 55
        XCTAssertTrue(evaluate(&engine, next).contains { $0.kind == .forecast })
    }

    func testForecastStillWorksWhenSeparateLowWarningIsDisabled() {
        var engine = StudioAlertEngine(); var p = preferences; p.lowAllowance = false
        var baseline = observation(9); baseline.weekly?.reset = now.addingTimeInterval(5 * 86400)
        _ = evaluate(&engine, baseline, preferences: p)
        var next = baseline; next.fetchedAt = now.addingTimeInterval(300); next.weekly?.remaining = 8
        XCTAssertTrue(evaluate(&engine, next, preferences: p).contains { $0.kind == .forecast })
    }

    func testContinuousDropAlertsOnceAndRearmsAfterQuietWindow() throws {
        var engine = StudioAlertEngine()
        var p = preferences; p.claudeDrop.enabled = true
        _ = evaluate(&engine, observation(), preferences: p)
        let first = try XCTUnwrap(evaluate(&engine, observation(69, offset: 300), preferences: p).first)
        XCTAssertEqual(first.kind, .drop)
        engine.acknowledge(first, now: first.createdAt)
        XCTAssertFalse(evaluate(&engine, observation(65, offset: 600), preferences: p).contains { $0.kind == .drop })
        _ = evaluate(&engine, observation(65, offset: 900), preferences: p)
        _ = evaluate(&engine, observation(65, offset: 1800), preferences: p)
        let second = try XCTUnwrap(evaluate(&engine, observation(54, offset: 2100), preferences: p).first)
        XCTAssertEqual(second.kind, .drop)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testExpiryReminderHasDistinct24HourAnd2HourStages() throws {
        var engine = StudioAlertEngine()
        var first = observation(); first.credits = 1; first.expiries = [now.addingTimeInterval(23 * 3600)]
        let a = try XCTUnwrap(evaluate(&engine, first).first)
        XCTAssertEqual(a.kind, .expiry)
        engine.acknowledge(a, now: now)
        var next = first; next.fetchedAt = now.addingTimeInterval(22 * 3600)
        let b = try XCTUnwrap(evaluate(&engine, next).first)
        XCTAssertEqual(b.kind, .expiry)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testFailedDeliveryRemainsPendingUntilAcknowledged() throws {
        var engine = StudioAlertEngine()
        _ = evaluate(&engine, observation())
        let event = try XCTUnwrap(evaluate(&engine, observation(5, offset: 300)).first)
        XCTAssertEqual(evaluate(&engine, observation(5, offset: 300)).first?.id, event.id)
        engine.acknowledge(event, now: event.createdAt)
        XCTAssertTrue(evaluate(&engine, observation(5, offset: 300)).isEmpty)
    }

    func testPendingLowAlertIsNotSentAfterRefill() {
        var engine = StudioAlertEngine()
        _ = evaluate(&engine, observation())
        _ = evaluate(&engine, observation(5, offset: 300))
        var next = observation(90, offset: 600); next.weekly?.reset = now.addingTimeInterval(7 * 86400)
        XCTAssertFalse(evaluate(&engine, next).contains { $0.kind == .low })
    }

    func testDisabledEngineStillUpdatesBaselineWithoutSending() {
        var engine = StudioAlertEngine(); var p = preferences; p.enabled = false
        XCTAssertTrue(evaluate(&engine, observation(10), preferences: p).isEmpty)
        XCTAssertEqual(engine.accounts["claude:A"]?.previous.weekly?.remaining, 10)
    }

    func testMorningReportAtSevenLondonTimeAndOnlyOncePerDay() throws {
        var engine = StudioAlertEngine(); let p = StudioAlertPreferences()
        let seven = ISO8601DateFormatter().date(from: "2026-11-01T07:00:00Z")!
        var reading = observation(); reading.fetchedAt = seven
        XCTAssertTrue(engine.evaluate([reading], now: seven.addingTimeInterval(-1), preferences: p).isEmpty)
        let event = try XCTUnwrap(engine.evaluate([reading], now: seven, preferences: p).first { $0.kind == .morning })
        engine.acknowledge(event, now: seven)
        engine = try JSONDecoder().decode(StudioAlertEngine.self, from: JSONEncoder().encode(engine))
        XCTAssertFalse(engine.evaluate([reading], now: seven.addingTimeInterval(60), preferences: p).contains { $0.kind == .morning })
    }

    func testLondonMorningFollowsBritishSummerTime() {
        let p = StudioAlertPreferences()
        let before = ISO8601DateFormatter().date(from: "2026-03-29T05:59:00Z")!
        let due = before.addingTimeInterval(60)
        XCTAssertNil(StudioAlertEngine.morningDay(now: before, preferences: p))
        XCTAssertEqual(StudioAlertEngine.morningDay(now: due, preferences: p), "2026-03-29")
    }

    func testMorningCatchupHasFourHourLimit() {
        let p = StudioAlertPreferences()
        let ten = ISO8601DateFormatter().date(from: "2026-11-01T10:00:00Z")!
        XCTAssertNotNil(StudioAlertEngine.morningDay(now: ten, preferences: p))
        XCTAssertNil(StudioAlertEngine.morningDay(now: ten.addingTimeInterval(3600), preferences: p))
    }

    func testMorningLabelsUnavailableReadingsInsteadOfClaimingTheirPercentage() {
        var reading = observation(80); reading.fresh = false
        let text = StudioAlertText.morning([reading], now: now, preferences: preferences)
        XCTAssertTrue(text.contains("reading unavailable"))
        XCTAssertFalse(text.contains("80%"))
    }

    func testSpareWarningsDoNotWakeUserAtNight() {
        var p = preferences; p.spare = true
        let night = ISO8601DateFormatter().date(from: "2026-11-01T01:00:00Z")!
        var engine = StudioAlertEngine()
        var a = observation(90); a.fetchedAt = night; a.weekly?.reset = night.addingTimeInterval(12 * 3600)
        _ = engine.evaluate([a], now: night, preferences: p)
        a.fetchedAt = night.addingTimeInterval(300)
        XCTAssertFalse(engine.evaluate([a], now: a.fetchedAt, preferences: p).contains { $0.kind == .spare })
    }

    func testZeroCreditsSuppressesLeftoverExpiryDates() {
        var engine = StudioAlertEngine()
        var reading = observation(); reading.expiries = [now.addingTimeInterval(3600)]
        XCTAssertTrue(evaluate(&engine, reading).isEmpty)
    }

    func testNaturalWeeklyRenewalIsNotAnnouncedAsEarlyReset() {
        var engine = StudioAlertEngine()
        _ = evaluate(&engine, observation())
        var reading = observation(100, offset: 2 * 86400 + 60)
        reading.weekly?.reset = reading.fetchedAt.addingTimeInterval(7 * 86400)
        XCTAssertFalse(evaluate(&engine, reading).contains { $0.kind == .reset })
    }

    func testReadingsRecoveryRequiresObservedUnavailability() {
        var engine = StudioAlertEngine()
        _ = evaluate(&engine, observation())
        var unavailable = observation(offset: 300); unavailable.fresh = false
        _ = evaluate(&engine, unavailable)
        let restored = evaluate(&engine, observation(offset: 600))
        XCTAssertEqual(restored.first?.kind, .recovery)
        XCTAssertTrue(restored.first?.title.contains("Readings Restored") ?? false)
    }

    func testOnlyOneMonitorCanHoldProcessLock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var first: StudioProcessLock? = StudioProcessLock(directory: directory)
        let second = StudioProcessLock(directory: directory)
        XCTAssertTrue(try XCTUnwrap(first).acquire())
        XCTAssertFalse(try second.acquire())
        first = nil
        XCTAssertTrue(try second.acquire())
    }
}
