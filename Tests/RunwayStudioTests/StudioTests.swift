import XCTest
@testable import RunwayStudioKit

final class StudioTests: XCTestCase {
    func testMissingDailyRecordsStayUnknownWhileRecordedZeroStaysZero() {
        let missing = StudioDay(date: "2026-10-31", totalTokens: nil, costUSD: nil)
        let zero = StudioDay(date: "2026-10-30", totalTokens: 0, costUSD: nil)
        XCTAssertNil(StudioDay.totalRecordedTokens([missing]))
        XCTAssertNil(StudioDay.totalRecordedTokens([]))
        XCTAssertEqual(StudioDay.totalRecordedTokens([missing, zero]), 0)
    }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func snapshot(used: Double = 35, age: TimeInterval = 0, resetIn: TimeInterval = 2 * 86400) -> StudioSnapshot {
        StudioSnapshot(providerID: "claude", displayName: "Claude", refreshedAt: now.addingTimeInterval(-age),
                       lines: [StudioLine(type: "progress", label: "Weekly", used: used, limit: 100,
                                          resetsAt: now.addingTimeInterval(resetIn), periodDurationMs: 604_800_000)])
    }

    func testArchiveRecordsOnlyObservedPointsAndDeduplicatesPolling() {
        var archive = StudioArchive()
        archive.record(snapshot(), identity: "account-A", now: now)
        archive.record(snapshot(), identity: "account-A", now: now.addingTimeInterval(30))
        XCTAssertEqual(archive.readings.count, 1)
        XCTAssertEqual(archive.readings.first?.date, now)
        XCTAssertEqual(archive.readings.first?.remaining, 65)
    }

    func testAccountSwitchCannotReusePreviousCurve() {
        var archive = StudioArchive()
        archive.record(snapshot(), identity: "account-A", now: now)
        XCTAssertEqual(archive.current(account: "claude:account-B", reset: now.addingTimeInterval(2 * 86400)).count, 0)
    }

    func testStaleFailedUnknownAndElapsedWindowsNeverCreateHistory() {
        var archive = StudioArchive()
        archive.record(snapshot(age: 400), identity: "account-A", now: now)
        archive.record(snapshot(), identity: nil, now: now)
        archive.record(snapshot(resetIn: -1), identity: "account-A", now: now)
        var warning = snapshot(); warning.warning = "Re-login"
        archive.record(warning, identity: "account-A", now: now)
        XCTAssertTrue(archive.readings.isEmpty)
    }

    func testEarlyResetCreatesSeparateWindow() {
        var archive = StudioArchive()
        archive.record(snapshot(), identity: "A", now: now)
        var next = snapshot(used: 1, resetIn: 7 * 86400 - 30)
        next.refreshedAt = now.addingTimeInterval(30)
        archive.record(next, identity: "A", now: now.addingTimeInterval(30))
        XCTAssertEqual(archive.current(account: "claude:A", reset: next.weekly!.resetsAt!).count, 1)
    }

    func testPaceForecastAndStaleSuppression() {
        let line = snapshot(used: 80, resetIn: 5 * 86400).weekly!
        let forecast = StudioPace(line: line, stale: false, now: now)
        XCTAssertEqual(forecast.state, .tight)
        XCTAssertEqual(forecast.exhaustion!.timeIntervalSince(now), 43200, accuracy: 0.001)
        let stale = StudioPace(line: line, stale: true, now: now)
        XCTAssertEqual(stale.state, .stale)
        XCTAssertNil(stale.exhaustion)
    }

    func testSmallCoarsePercentDoesNotProduceAlarm() {
        let forecast = StudioPace(line: snapshot(used: 1, resetIn: 7 * 86400 - 700).weekly!, stale: false, now: now)
        XCTAssertEqual(forecast.state, .available)
        XCTAssertNil(forecast.exhaustion)
    }

    func testElapsedResetIsPendingNotAvailable() {
        let pace = StudioPace(line: snapshot(resetIn: -10).weekly!, stale: false, now: now)
        XCTAssertEqual(pace.state, .pending)
        XCTAssertNil(pace.exhaustion)
    }

    func testMissingDaysStayUnknownAndModelRangeMatchesChart() {
        let calendar = Calendar(identifier: .gregorian)
        let today = StudioDay.key(now, calendar: calendar)
        let history = StudioUsageHistory(series: .init(daily: [.init(date: today, totalTokens: 100, costUSD: 1)]),
            modelUsage: .init(daily: [.init(date: today, models: [.init(model: "a", totalTokens: 100, costUSD: 1)]),
                                     .init(date: "2020-01-01", models: [.init(model: "b", totalTokens: 900, costUSD: 9)])]))
        let days = history.days(count: 7, now: now, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertNil(days[0].totalTokens)
        XCTAssertEqual(history.models(in: Set(days.map(\.date))).map(\.model), ["a"])
    }

    func testCacheAcceptsFractionalAndWholeSecondProviderDates() throws {
        let payload = """
        {"snapshots":{"claude":{"providerID":"claude","displayName":"Claude","refreshedAt":"2026-10-31T14:00:00.900Z","lines":[{"type":"progress","label":"Weekly","used":20,"limit":100,"resetsAt":"2026-11-01T14:00:00Z"}]}},"producedByIdentityKeys":{"claude":"A"}}
        """
        let decoded = try StudioCache.decode(Data(payload.utf8))
        XCTAssertEqual(decoded.snapshots["claude"]?.weekly?.remaining, 80)
    }

    func testNonFiniteOrInvalidQuotaHasNoGaugeValue() {
        var line = snapshot().weekly!
        line.limit = 0
        XCTAssertNil(line.remaining)
        line.limit = 100; line.used = .nan
        XCTAssertNil(line.remaining)
    }

    func testGlidePathBreaksAcrossUnobservedGaps() {
        let readings = [0.0, 300, 2500, 2800].map {
            StudioReading(account: "A", date: now.addingTimeInterval($0), reset: now.addingTimeInterval(86400), duration: 604800, remaining: 50)
        }
        XCTAssertEqual(StudioGlidePoint.segments(readings).map(\.segment), [0, 0, 1, 1])
    }
}
