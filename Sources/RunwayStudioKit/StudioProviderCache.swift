import CryptoKit
import Foundation
import Runway

/// Studio owns its provider cache. The old preferences are an optional one-time migration source.
@MainActor final class StudioProviderCache {
    static let shared = StudioProviderCache(directory: defaultDirectory)
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/RunwayStudio", isDirectory: true)
    }
    let url: URL
    private let directory: URL
    private let legacyURL: URL
    private var defaults: UserDefaults?
    private let snapshotKey = "runway.providerSnapshots.v9"

    init(directory: URL, legacyURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.mattstallone.runway.plist")) {
        self.directory = directory
        self.url = directory.appendingPathComponent("provider-cache.json")
        self.legacyURL = legacyURL
    }

    func read() throws -> StudioCache {
        try prepare()
        return try StudioCache.decode(Data(contentsOf: url))
    }

    func prepare() throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        var data = Data(#"{"snapshots":{},"producedByIdentityKeys":{}}"#.utf8)
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: legacyURL), format: nil)
            if let dictionary = plist as? [String: Any], let old = dictionary[snapshotKey] as? Data {
                _ = try StudioCache.decode(old)
                data = old
            }
        }
        try write(data)
    }

    private func engineDefaults() throws -> UserDefaults {
        if let defaults { return defaults }
        try prepare()
        let hash = SHA256.hash(data: Data(directory.standardizedFileURL.path.utf8)).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
        guard let value = UserDefaults(suiteName: "local.runway.studio.providers.\(hash)") else {
            throw CocoaError(.fileReadUnknown)
        }
        // Studio's file is authoritative. No reads or writes to the original app's defaults.
        let data = try Data(contentsOf: url)
        _ = try StudioCache.decode(data)
        value.set(data, forKey: snapshotKey)
        defaults = value
        return value
    }

    func run(_ arguments: [String], timeout: TimeInterval) async throws -> StudioRefreshProcessOutput {
        guard let family = arguments.first, ["claude", "codex"].contains(family.split(separator: "@").first.map(String.init) ?? "") else {
            throw UsageReaderError.unknownProvider(arguments.first ?? "")
        }
        try Task.checkCancellation()
        let settings = try engineDefaults()
        let result = try await UsageReader(userDefaults: settings).read(providerID: family, force: true)
        try Task.checkCancellation()
        guard let data = settings.data(forKey: snapshotKey) else { throw CocoaError(.fileReadCorruptFile) }
        _ = try StudioCache.decode(data)
        try write(data)
        return StudioRefreshProcessOutput(status: result.warnings.isEmpty ? 0 : 4, stdout: result.data, stderr: Data())
    }

    private func write(_ data: Data) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
