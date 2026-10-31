import Foundation
import XCTest
@testable import RunwayStudioKit

final class StudioImportedHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func row(account: String = "source-a", offset: TimeInterval = -300, used: Double = 40) -> [String: Any] {
        ["account": account, "date": now.addingTimeInterval(offset).timeIntervalSinceReferenceDate,
         "resetsAt": now.addingTimeInterval(86400).timeIntervalSinceReferenceDate, "usedPercent": used]
    }
    private func data(_ history: [Any]) throws -> Data { try JSONSerialization.data(withJSONObject: ["history": history]) }

    func testImportsActualSevenDayPointsWithSeparateSourceAccountAndProviderMapping() throws {
        let imported = try StudioImportedHistory.decode(data(["claude", [row(offset: -5 * 86400), row()], "openai", [row(used: 70)]]), now: now)
        XCTAssertEqual(imported.readings.count, 3)
        let claude = imported.current(family: "claude", reset: now.addingTimeInterval(86400))
        XCTAssertEqual(claude.count, 2)
        XCTAssertEqual(claude[0].date, now.addingTimeInterval(-5 * 86400))
        XCTAssertEqual(claude[0].remaining, 60)
        XCTAssertEqual(claude[0].account, "agent-runway:claude:source-a")
        XCTAssertEqual(imported.windows(family: "codex").first?.readings.first?.remaining, 30)
        XCTAssertTrue(imported.current(family: "claude", reset: now.addingTimeInterval(90000)).isEmpty)
    }

    func testRoundedImportedResetTimesStayInOneWeeklyWindow() throws {
        let first = row(offset: -600)
        var last = row()
        last["resetsAt"] = now.addingTimeInterval(86460).timeIntervalSinceReferenceDate
        let imported = try StudioImportedHistory.decode(data(["claude", [first, last]]), now: now)
        XCTAssertEqual(imported.windows(family: "claude").count, 1)
        XCTAssertEqual(imported.current(family: "claude", reset: now.addingTimeInterval(86400)).count, 2)
        XCTAssertNotEqual(imported.readings[0].reset, imported.readings[1].reset)
    }

    func testMultipleImportedAccountsAreNeverCombinedOrAssignedToNativeAccount() throws {
        let imported = try StudioImportedHistory.decode(data(["claude", [row(), row(account: "source-b")]]), now: now)
        XCTAssertEqual(imported.readings.count, 2)
        XCTAssertTrue(imported.windows(family: "claude").isEmpty)
        XCTAssertTrue(imported.readings.allSatisfy { $0.account.hasPrefix("agent-runway:") })
    }

    func testOutOfWindowFutureAndDuplicateRecordsDoNotCreateInventedHistory() throws {
        let imported = try StudioImportedHistory.decode(data(["claude", [row(), row(), row(offset: 1000), row(offset: -8 * 86400)]]), now: now)
        XCTAssertEqual(imported.readings.count, 1)
        XCTAssertEqual(StudioGlidePoint.segments(imported.readings).count, 1)
        XCTAssertThrowsError(try StudioImportedHistory.decode(data(["claude", [row(used: 101)]]), now: now))
    }

    func testImportIsCopiedOnceAndWorksWithoutOriginalData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.json")
        try data(["claude", [row()]]).write(to: source)
        let imported = try StudioImportedHistory.load(directory: root, source: source, now: now)
        XCTAssertEqual(imported.readings.count, 1)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try StudioImportedHistory.load(directory: root, source: source, now: now).readings, imported.readings)
        let destination = root.appendingPathComponent("imported-allowance-history.json")
        try Data("invalid".utf8).write(to: destination)
        XCTAssertThrowsError(try StudioImportedHistory.load(directory: root, source: source, now: now))
        XCTAssertEqual(try Data(contentsOf: destination), Data("invalid".utf8))
    }
}
