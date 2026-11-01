import Foundation
import XCTest
@testable import RunwayStudioKit

final class StudioDocumentationTests: XCTestCase {
    @MainActor func testDocumentationPreviewHasNoPersonalHistoryOrActiveProviderEngine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StudioStore.documentationPreview(directory: root)
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertTrue(store.identities.isEmpty)
        XCTAssertTrue(store.archive.readings.isEmpty)
        XCTAssertTrue(store.importedHistory.readings.isEmpty)
        XCTAssertTrue(store.activityEvents.isEmpty)
        XCTAssertFalse(store.polling.active)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.providerCache.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-state.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("polling-state.json").path))
    }
}
