import Foundation
import XCTest
@testable import RunwayStudioKit

final class StudioManualRefreshTests: XCTestCase {
    func testShutdownTerminatesOnlyRegisteredHelperProcesses() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]
        try process.run()
        let registry = StudioActiveRefreshes()
        registry.add(process)
        registry.cancelAll()
        process.waitUntilExit()
        registry.remove(process)
        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
    }
    func testRefreshPassesExactCardAndForceAndUsesReportedTimestamp() async {
        let output = Data(#"{"schema":"runway.limits.v1","providers":{"codex@abc":{"fetchedAt":"2026-01-01T12:30:00.000Z","resources":{}}},"errors":[]}"#.utf8)
        let client = StudioManualRefreshClient(runner: { args, timeout in
            XCTAssertEqual(args, ["codex@abc", "--force"])
            XCTAssertEqual(timeout, 45)
            return StudioRefreshProcessOutput(status: 0, stdout: output, stderr: Data())
        })
        let result = await client.refresh(providerID: "codex@abc")
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.fetchedAt?.timeIntervalSince1970, 1_767_270_600)
        XCTAssertNil(result.warning)
        XCTAssertEqual(result.fetchedAtByProvider["codex@abc"], result.fetchedAt)
    }
    func testFailureAndPartialResponseAreNotReportedAsFullSuccess() async {
        let partial = Data(#"{"schema":"runway.limits.v1","providers":{"claude@abc":{"fetchedAt":"2026-01-01T12:30:00Z","resources":{}}},"errors":[]}"#.utf8)
        let client = StudioManualRefreshClient(runner: { _, _ in StudioRefreshProcessOutput(status: 4, stdout: partial, stderr: Data()) })
        let result = await client.refresh(providerID: "claude@abc")
        XCTAssertTrue(result.succeeded)
        XCTAssertNotNil(result.warning)
        let timeout = StudioManualRefreshClient(runner: { _, _ in throw StudioRefreshProcessError.timedOut })
        let timeoutResult = await timeout.refresh(providerID: "claude@abc")
        XCTAssertFalse(timeoutResult.succeeded)
        let invalid = StudioManualRefreshClient(runner: { _, _ in StudioRefreshProcessOutput(status: 0, stdout: Data("{}".utf8), stderr: Data()) })
        let invalidResult = await invalid.refresh(providerID: "codex@abc")
        XCTAssertFalse(invalidResult.succeeded)
    }
    func testFamilyResponseKeepsCardResultsSeparate() async {
        let json = Data(#"{"schema":"runway.limits.v1","providers":{"codex":{"fetchedAt":"2026-01-01T12:30:00Z","resources":{}},"codex@extra":{"fetchedAt":"2026-01-01T12:31:00Z","resources":{}}},"errors":[{"providerId":"codex@extra","message":"failure"}]}"#.utf8)
        let client = StudioManualRefreshClient(runner: { args, _ in
            XCTAssertEqual(args, ["codex", "--force"])
            return StudioRefreshProcessOutput(status: 4, stdout: json, stderr: Data())
        })
        let result = await client.refresh(providerID: "codex")
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(Set(result.fetchedAtByProvider.keys), ["codex"])
        XCTAssertEqual(result.failedProviderIDs, ["codex@extra"])
        XCTAssertNotNil(result.warning)
    }

}
