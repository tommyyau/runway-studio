import Foundation
import Observation

enum StudioMenuDisplay: String, Codable, CaseIterable, Identifiable {
    case barsAndPercentages, bars, percentages
    var id: Self { self }
    var title: String {
        switch self {
        case .barsAndPercentages: "Bars & Percentages"
        case .bars: "Bars Only"
        case .percentages: "Percentages Only"
        }
    }
    var showsBars: Bool { self != .percentages }
    var showsPercentages: Bool { self != .bars }
    var width: Double { self == .barsAndPercentages ? 72 : (self == .bars ? 40 : 49) }
}

struct StudioDisplayPreferences: Codable, Equatable {
    var menuDisplay: StudioMenuDisplay = .barsAndPercentages
    var menuAccounts: [String: String] = [:]
    var showSummary = true
    var showMenuActivity = true
    var showModelLimits = true
    var showServiceStatus = true
    var showRefreshHealth = true
    var activityDays = 1
    var showAPIValue = false
}

@MainActor @Observable final class StudioDisplayStore {
    var preferences = StudioDisplayPreferences() { didSet { save() } }
    private(set) var error: String?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var writable = true

    init(directory: URL) {
        url = directory.appendingPathComponent("display-preferences.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let decoded = try JSONDecoder().decode(StudioDisplayPreferences.self, from: Data(contentsOf: url))
            guard [1, 7, 14, 30].contains(decoded.activityDays) else {
                throw CocoaError(.coderReadCorrupt)
            }
            preferences = decoded
        } catch {
            writable = false
            self.error = "Display preferences could not be read. The saved file has been preserved. \(error.localizedDescription)"
            NSLog("Runway Studio: %@", self.error!)
        }
    }

    private func save() {
        guard writable else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(preferences).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            error = nil
        } catch {
            self.error = "Display preferences could not be saved. \(error.localizedDescription)"
            NSLog("Runway Studio: %@", self.error!)
        }
    }
}
