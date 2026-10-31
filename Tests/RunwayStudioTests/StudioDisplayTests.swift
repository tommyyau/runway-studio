import Foundation
import XCTest
@testable import RunwayStudioKit

final class StudioDisplayTests: XCTestCase {
    @MainActor func testChoicesSurviveRestartWithoutChangingOtherState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let display = StudioDisplayStore(directory: root)
        XCTAssertEqual(display.preferences.menuDisplay, .barsAndPercentages)
        display.preferences.menuDisplay = .bars
        display.preferences.showSummary = false
        display.preferences.activityDays = 14
        display.preferences.menuAccounts["claude"] = "claude@work"
        let restored = StudioDisplayStore(directory: root)
        XCTAssertEqual(display.preferences, restored.preferences)
        XCTAssertNil(restored.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("polling-state.json").path))
        let permissions = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("display-preferences.json").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    @MainActor func testCorruptPreferencesArePreservedWhenControlsChange() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("display-preferences.json")
        let bad = Data("broken".utf8)
        try bad.write(to: url)
        let display = StudioDisplayStore(directory: root)
        XCTAssertNotNil(display.error)
        display.preferences.showSummary = false
        XCTAssertEqual(try Data(contentsOf: url), bad)
    }

    func testPreferredMenuAccountDoesNotCombineAllowancesAndFallsBackIfMissing() {
        let now = Date()
        func card(_ id: String, _ used: Double) -> StudioSnapshot {
            StudioSnapshot(providerID: id, displayName: id, refreshedAt: now,
                lines: [StudioLine(type: "progress", label: "Weekly", used: used, limit: 100)])
        }
        let cards = [card("claude", 20), card("claude@work", 70)]
        let preferred = StudioMenuEntry.make(snapshots: cards, staleIDs: [], now: now,
            preferredAccounts: ["claude": "claude@work"])
        XCTAssertEqual(preferred.count, 1)
        XCTAssertEqual(preferred[0].id, "claude@work")
        XCTAssertEqual(preferred[0].weekly!, 30, accuracy: 0.00001)
        let fallback = StudioMenuEntry.make(snapshots: cards, staleIDs: [], now: now,
            preferredAccounts: ["claude": "claude@removed"])
        XCTAssertEqual(fallback[0].id, "claude")
        XCTAssertEqual(fallback[0].weekly!, 80, accuracy: 0.00001)
    }
}
