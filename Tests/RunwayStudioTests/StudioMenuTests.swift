import XCTest
@testable import RunwayStudioKit

final class StudioMenuTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func snapshot(id: String = "claude", age: Double = 0, reset: Double = 1000) -> StudioSnapshot {
        StudioSnapshot(providerID: id, displayName: id, refreshedAt: now.addingTimeInterval(-age), lines: [
            StudioLine(type: "progress", label: "Weekly", used: 40, limit: 100,
                resetsAt: now.addingTimeInterval(reset), periodDurationMs: 604_800_000),
            StudioLine(type: "progress", label: "Session", used: 20, limit: 100,
                resetsAt: now.addingTimeInterval(500), periodDurationMs: 18_000_000)
        ])
    }

    func testSnapshotKeepsProviderOrderAndDoesNotSumAccounts() {
        let entries = StudioMenuEntry.make(snapshots: [snapshot(id: "codex"), snapshot(id: "claude@work"), snapshot()],
            staleIDs: [], now: now)
        XCTAssertEqual(entries.map(\.id), ["claude", "codex"])
        XCTAssertEqual(entries.first?.weekly, 60)
        XCTAssertEqual(entries.first?.session, 80)
        XCTAssertTrue(entries.first!.summary.contains("session 80% left, weekly 60% left"))
    }

    func testCachedOrFailedReadingKeepsLastKnownAllowanceAndIdentifiesCache() {
        for entry in [
            StudioMenuEntry.make(snapshots: [snapshot(age: 400)], staleIDs: [], now: now)[0],
            StudioMenuEntry.make(snapshots: [snapshot()], staleIDs: ["claude"], now: now)[0]
        ] {
            XCTAssertTrue(entry.stale)
            XCTAssertEqual(entry.primary, 60)
            XCTAssertEqual(entry.session, 80)
            XCTAssertEqual(entry.cells, 3)
            XCTAssertEqual(entry.level, .green)
            XCTAssertTrue(entry.summary.contains("cached"))
            XCTAssertTrue(entry.summary.contains("weekly 60% left"))
        }
    }

    func testTrafficLightThresholdsAndMissingReading() {
        XCTAssertEqual(StudioAllowanceLevel.remaining(100), .green)
        XCTAssertEqual(StudioAllowanceLevel.remaining(30.1), .green)
        XCTAssertEqual(StudioAllowanceLevel.remaining(30), .orange)
        XCTAssertEqual(StudioAllowanceLevel.remaining(10.1), .orange)
        XCTAssertEqual(StudioAllowanceLevel.remaining(10), .red)
        XCTAssertEqual(StudioAllowanceLevel.remaining(0), .red)
        XCTAssertEqual(StudioAllowanceLevel.remaining(nil), .unavailable)
        XCTAssertEqual(StudioAllowanceLevel.remaining(.nan), .unavailable)
    }

    func testExpiredQuotaWaitsForProviderAndFallsBackToSession() {
        var card = snapshot(reset: -1)
        let fallback = StudioMenuEntry.make(snapshots: [card], staleIDs: [], now: now)[0]
        XCTAssertNil(fallback.weekly)
        XCTAssertEqual(fallback.primary, 80)
        card.lines.removeLast()
        let pending = StudioMenuEntry.make(snapshots: [card], staleIDs: [], now: now)[0]
        XCTAssertNil(pending.primary)
        XCTAssertTrue(pending.summary.contains("awaiting reset"))
    }

    func testSessionOnlyAndAlternateAccountStillGetAnEntry() {
        var card = snapshot(id: "codex@work")
        card.lines.removeFirst()
        let entry = StudioMenuEntry.make(snapshots: [card], staleIDs: [], now: now)[0]
        XCTAssertEqual(entry.family, "codex")
        XCTAssertEqual(entry.primary, 80)
    }

    func testSegmentsDistinguishTinyAllowanceEmptyAndCompletelyFull() {
        XCTAssertEqual(StudioMenuEntry.cellCount(nil), 0)
        XCTAssertEqual(StudioMenuEntry.cellCount(.nan), 0)
        XCTAssertEqual(StudioMenuEntry.cellCount(0), 0)
        XCTAssertEqual(StudioMenuEntry.cellCount(0.1), 1)
        XCTAssertEqual(StudioMenuEntry.cellCount(60), 3)
        XCTAssertEqual(StudioMenuEntry.cellCount(99), 4)
        XCTAssertEqual(StudioMenuEntry.cellCount(100), 5)
    }
}
