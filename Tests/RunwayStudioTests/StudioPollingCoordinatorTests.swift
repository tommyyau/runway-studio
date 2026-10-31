import Foundation
import XCTest
@testable import RunwayStudioKit

private actor PollCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

@MainActor final class StudioPollingCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func card(at date: Date, waiting: Bool = false) -> StudioSnapshot {
        var card = StudioSnapshot(providerID: "claude", displayName: "Claude", refreshedAt: date,
            lines: [StudioLine(type: "progress", label: "Weekly", used: 30, limit: 100)])
        card.warningAction = waiting ? "wait" : nil
        return card
    }
    private func response(at date: Date) -> StudioRefreshProcessOutput {
        let stamp = ISO8601DateFormatter().string(from: date)
        return StudioRefreshProcessOutput(status: 0,
            stdout: Data("{\"schema\":\"runway.limits.v1\",\"providers\":{\"claude\":{\"fetchedAt\":\"\(stamp)\",\"resources\":{}}},\"errors\":[]}".utf8), stderr: Data())
    }
    func testAutomaticAndManualCallsCannotOverlapAndShareCooldown() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let calls = PollCallCounter(), response = response(at: now)
        let client = StudioManualRefreshClient { _, _ in
            await calls.increment()
            try await Task.sleep(for: .milliseconds(50))
            return response
        }
        let current = card(at: now), old = card(at: now.addingTimeInterval(-600)), instant = now
        let coordinator = StudioPollingCoordinator(directory: directory, client: client, clock: { instant },
            competitors: { [] }, readCache: { [current] })
        let task = Task { await coordinator.poll(snapshots: [old]) }
        while !coordinator.isPolling { await Task.yield() }
        let concurrent = await coordinator.poll(snapshots: [old])
        XCTAssertTrue(concurrent.contains("already running"))
        _ = await task.value
        _ = await coordinator.poll(snapshots: [current])
        let count = await calls.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(coordinator.nextAttempt(family: "claude"), now.addingTimeInterval(300))
    }
    func testCachedWaitIsPersistedAndDoesNotLaunchAHelper() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let calls = PollCallCounter(), instant = now
        let client = StudioManualRefreshClient { _, _ in
            await calls.increment(); throw URLError(.cannotConnectToHost)
        }
        var coordinator: StudioPollingCoordinator? = StudioPollingCoordinator(directory: directory, client: client,
            clock: { instant }, competitors: { [] })
        _ = await coordinator!.poll(snapshots: [card(at: now.addingTimeInterval(-600), waiting: true)])
        XCTAssertEqual(coordinator!.nextAttempt(family: "claude"), now.addingTimeInterval(900))
        coordinator = nil
        let restored = StudioPollingCoordinator(directory: directory, client: client, clock: { instant }, competitors: { [] })
        XCTAssertEqual(restored.nextAttempt(family: "claude"), now.addingTimeInterval(900))
        _ = await restored.poll(snapshots: [card(at: now, waiting: true)])
        let count = await calls.count
        XCTAssertEqual(count, 0)
    }
    func testCompetingTrackerAndCorruptScheduleFailClosed() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let calls = PollCallCounter(), instant = now
        let client = StudioManualRefreshClient { _, _ in await calls.increment(); throw URLError(.cannotConnectToHost) }
        var coordinator: StudioPollingCoordinator? = StudioPollingCoordinator(directory: directory, client: client,
            clock: { instant }, competitors: { ["Agent Runway"] })
        let text = await coordinator!.poll(snapshots: [card(at: now.addingTimeInterval(-600))])
        XCTAssertTrue(text.contains("Agent Runway"))
        coordinator = nil
        try Data("not valid json".utf8).write(to: directory.appendingPathComponent("polling-state.json"))
        let invalid = StudioPollingCoordinator(directory: directory, client: client, clock: { instant }, competitors: { [] })
        XCTAssertNotNil(invalid.problem)
        _ = await invalid.poll(snapshots: [card(at: now.addingTimeInterval(-600))])
        let count = await calls.count
        XCTAssertEqual(count, 0)
    }
    func testAHelperTimestampCannotMakeAnOlderUnpublishedCacheReadingFresh() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let result = response(at: now), instant = now
        let oldValid = card(at: now.addingTimeInterval(-60))
        let coordinator = StudioPollingCoordinator(directory: directory,
            client: StudioManualRefreshClient { _, _ in result }, clock: { instant }, competitors: { [] }, readCache: { [oldValid] })
        _ = await coordinator.poll(snapshots: [card(at: now.addingTimeInterval(-600))])
        XCTAssertTrue(coordinator.hasFailure(family: "claude"))
        XCTAssertEqual(coordinator.nextAttempt(family: "claude"), now.addingTimeInterval(900))
        coordinator.reconcile(snapshots: [card(at: now)])
        XCTAssertFalse(coordinator.hasFailure(family: "claude"))
        XCTAssertEqual(coordinator.nextAttempt(family: "claude"), now.addingTimeInterval(300))
    }
    func testASecondCoordinatorCannotOwnTheSamePollingDirectory() {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = StudioPollingCoordinator(directory: directory, competitors: { [] })
        let second = StudioPollingCoordinator(directory: directory, competitors: { [] })
        XCTAssertTrue(first.active)
        XCTAssertFalse(second.active)
        withExtendedLifetime(first) {}
    }
    func testCachedWaitAutomaticallyRetriesAfterDeadlineAndCanRecover() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let calls = PollCallCounter(), future = now.addingTimeInterval(900)
        let result = response(at: future), recovered = card(at: future)
        var clock = now
        let coordinator = StudioPollingCoordinator(directory: directory,
            client: StudioManualRefreshClient { _, _ in await calls.increment(); return result },
            clock: { clock }, competitors: { [] }, readCache: { [recovered] })
        let waiting = card(at: now.addingTimeInterval(-600), waiting: true)
        _ = await coordinator.poll(snapshots: [waiting])
        XCTAssertEqual(coordinator.nextAttempt(family: "claude"), future)
        clock = future
        let message = await coordinator.poll(snapshots: [waiting])
        XCTAssertTrue(message.contains("Updated Claude"))
        XCTAssertFalse(coordinator.hasFailure(family: "claude"))
        XCTAssertEqual(coordinator.nextAttempt(family: "claude"), future.addingTimeInterval(300))
        let count = await calls.count
        XCTAssertEqual(count, 1)
    }
    func testLatePublicationClearsSchedulingFailureWithoutMakingOldDataCurrent() async {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let result = response(at: now), old = card(at: now.addingTimeInterval(-60))
        var clock = now
        let coordinator = StudioPollingCoordinator(directory: directory,
            client: StudioManualRefreshClient { _, _ in result }, clock: { clock },
            competitors: { [] }, readCache: { [old] })
        _ = await coordinator.poll(snapshots: [card(at: now.addingTimeInterval(-600))])
        XCTAssertTrue(coordinator.hasFailure(family: "claude"))
        clock = now.addingTimeInterval(1000)
        let published = card(at: now)
        coordinator.reconcile(snapshots: [published])
        XCTAssertFalse(coordinator.hasFailure(family: "claude"))
        XCTAssertTrue(published.isStale(now: clock))
        XCTAssertEqual(coordinator.nextAttempt(family: "claude"), now.addingTimeInterval(300))
    }
}
