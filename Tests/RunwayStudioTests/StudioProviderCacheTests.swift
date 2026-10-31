import Foundation
import XCTest
@testable import RunwayStudioKit

final class StudioProviderCacheTests: XCTestCase {
    @MainActor func testCleanInstallBootstrapsWithoutOriginalAppOrPreferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = StudioProviderCache(directory: root, legacyURL: root.appendingPathComponent("absent.plist"))
        let payload = try cache.read()
        XCTAssertTrue(payload.snapshots.isEmpty)
        XCTAssertTrue(payload.producedByIdentityKeys.isEmpty)
        let permissions = try FileManager.default.attributesOfItem(atPath: cache.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    @MainActor func testMigrationIsOneTimeAndPreservesIdentityAndProviderTimestamp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = root.appendingPathComponent("legacy.plist")
        let original = Data(#"{"snapshots":{"claude":{"providerID":"claude","displayName":"Claude","refreshedAt":"2026-01-01T12:30:00Z","lines":[]}},"producedByIdentityKeys":{"claude":"account-a"}}"#.utf8)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["runway.providerSnapshots.v9": original], format: .binary, options: 0)
        try plist.write(to: legacy)
        let cache = StudioProviderCache(directory: root, legacyURL: legacy)
        let first = try cache.read()
        XCTAssertEqual(first.producedByIdentityKeys["claude"], "account-a")
        XCTAssertEqual(first.snapshots["claude"]?.refreshedAt.timeIntervalSince1970, 1_767_270_600)
        // Removing the old preferences cannot break subsequent reads, even after restarting Studio.
        try FileManager.default.removeItem(at: legacy)
        let restarted = StudioProviderCache(directory: root, legacyURL: legacy)
        XCTAssertEqual(try restarted.read().producedByIdentityKeys["claude"], "account-a")
        XCTAssertEqual(try Data(contentsOf: cache.url), original)
    }

    @MainActor func testInvalidOwnedCacheIsPreservedRatherThanReimported() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = StudioProviderCache(directory: root, legacyURL: root.appendingPathComponent("absent"))
        let bad = Data("damaged".utf8)
        try bad.write(to: cache.url)
        XCTAssertThrowsError(try cache.read())
        XCTAssertEqual(try Data(contentsOf: cache.url), bad)
    }
}
