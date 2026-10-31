import Foundation
import XCTest
@testable import RunwayStudioKit

final class StudioPollingPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testManualAndAutomaticShareSuccessCooldown() {
        var state = StudioPollState()
        XCTAssertTrue(state.begin(family: "claude", now: now))
        XCTAssertFalse(state.canAttempt(family: "claude", now: now.addingTimeInterval(1)))
        XCTAssertEqual(state.nextAllowed(family: "claude"), now.addingTimeInterval(900))
        state.finish(family: "claude", outcome: .success, now: now)
        XCTAssertEqual(state.nextAllowed(family: "claude"), now.addingTimeInterval(300))
        XCTAssertFalse(state.begin(family: "claude", now: now.addingTimeInterval(299)))
        XCTAssertTrue(state.begin(family: "claude", now: now.addingTimeInterval(300)))
        XCTAssertTrue(state.canAttempt(family: "codex", now: now))
    }

    func testFailuresBackOffToTwoHoursAndSuccessResets() {
        var state = StudioPollState()
        for (index, delay) in [900.0, 1800, 3600, 7200, 7200].enumerated() {
            let instant = now.addingTimeInterval(Double(index) * 10000)
            XCTAssertTrue(state.begin(family: "claude", now: instant))
            state.finish(family: "claude", outcome: .failure, now: instant)
            XCTAssertEqual(state.nextAllowed(family: "claude"), instant.addingTimeInterval(delay))
        }
        let later = now.addingTimeInterval(60000)
        XCTAssertTrue(state.begin(family: "claude", now: later))
        state.finish(family: "claude", outcome: .success, now: later)
        XCTAssertEqual(state.records["claude"]?.consecutiveFailures, 0)
        XCTAssertEqual(state.nextAllowed(family: "claude"), later.addingTimeInterval(300))
    }

    func testRateLimitDeadlineCannotBeShortenedBySuccessOrShorterRetry() {
        var state = StudioPollState()
        XCTAssertTrue(state.begin(family: "claude", now: now))
        state.finish(family: "claude", outcome: .rateLimited(retryAfter: 10000), now: now)
        XCTAssertEqual(state.nextAllowed(family: "claude"), now.addingTimeInterval(10000))
        state.finish(family: "claude", outcome: .success, now: now.addingTimeInterval(1))
        XCTAssertEqual(state.nextAllowed(family: "claude"), now.addingTimeInterval(10000))
        state.finish(family: "claude", outcome: .rateLimited(retryAfter: 1), now: now.addingTimeInterval(2))
        XCTAssertEqual(state.nextAllowed(family: "claude"), now.addingTimeInterval(10000))
        XCTAssertFalse(state.canAttempt(family: "claude", now: now.addingTimeInterval(9999)))
        XCTAssertTrue(state.canAttempt(family: "claude", now: now.addingTimeInterval(10000)))
    }

    func testCachedWaitAndPersistenceRecoverWithoutReseeding() throws {
        var state = StudioPollState()
        state.seedCachedWait(family: "claude", now: now)
        let saved = try JSONEncoder().encode(state)
        var restored = try JSONDecoder().decode(StudioPollState.self, from: saved)
        XCTAssertEqual(restored, state)
        restored.seedCachedWait(family: "claude", now: now.addingTimeInterval(899))
        XCTAssertFalse(restored.canAttempt(family: "claude", now: now.addingTimeInterval(899)))
        XCTAssertTrue(restored.begin(family: "claude", now: now.addingTimeInterval(900)))
        let interrupted = try JSONDecoder().decode(StudioPollState.self, from: JSONEncoder().encode(restored))
        XCTAssertFalse(interrupted.canAttempt(family: "claude", now: now.addingTimeInterval(901)))
        XCTAssertEqual(interrupted.records["claude"]?.lastAttempt, now.addingTimeInterval(900))
        XCTAssertEqual(interrupted.nextAllowed(family: "claude"), now.addingTimeInterval(1800))
    }
    func testRetryHintUsesOnlyKnownWarningShape() {
        XCTAssertNil(studioRetryHint("No retry hint"))
        XCTAssertEqual(studioRetryHint("Rate limited. Retrying in ~60m"), 3600)
        XCTAssertNil(studioRetryHint("Retrying in ~xm"))
        XCTAssertNil(studioRetryHint("Retrying in ~0m"))
    }

}
