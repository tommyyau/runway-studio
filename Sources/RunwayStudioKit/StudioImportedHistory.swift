import Foundation
import OSLog

/// User-owned exported data only. Source account IDs stay separate from Studio identities.
struct StudioImportedHistory: Codable {
    var readings: [StudioReading] = []

    func windows(family: String) -> [StudioWindow] {
        let prefix = "agent-runway:\(family):"
        let accounts = Set(readings.filter { $0.account.hasPrefix(prefix) }.map(\.account))
        // Several source accounts require an explicit selection; never mix them by provider.
        guard accounts.count == 1, let account = accounts.first else { return [] }
        var result: [StudioWindow] = []
        for reading in readings.filter({ $0.account == account }).sorted(by: { $0.date < $1.date }) {
            // The older exporter estimates resets from rounded countdowns. Coalesce that drift
            // for navigation only; retain every original sample timestamp and reset unchanged.
            if let index = result.firstIndex(where: { abs($0.reset.timeIntervalSince(reading.reset)) <= 120 }) {
                let values = result[index].readings + [reading]
                result[index] = StudioWindow(reset: reading.reset, duration: reading.duration, readings: values)
            } else {
                result.append(StudioWindow(reset: reading.reset, duration: reading.duration, readings: [reading]))
            }
        }
        return result.sorted { $0.reset < $1.reset }
    }

    func current(family: String, reset: Date) -> [StudioReading] {
        windows(family: family).first { abs($0.reset.timeIntervalSince(reset)) <= 120 }?.readings ?? []
    }

    static func decode(_ data: Data, now: Date) throws -> Self {
        guard data.count <= 8 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let history = object["history"] as? [Any], history.count.isMultiple(of: 2) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var result = Self()
        for index in stride(from: 0, to: history.count, by: 2) {
            guard let source = history[index] as? String,
                  let rows = history[index + 1] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
            guard let family = ["claude": "claude", "openai": "codex"][source] else { continue }
            for row in rows {
                guard let account = row["account"] as? String, !account.isEmpty,
                      let timestamp = row["date"] as? Double, timestamp.isFinite,
                      let reset = row["resetsAt"] as? Double, reset.isFinite,
                      let used = row["usedPercent"] as? Double, used.isFinite, (0...100).contains(used) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let date = Date(timeIntervalSinceReferenceDate: timestamp)
                let renewal = Date(timeIntervalSinceReferenceDate: reset)
                let duration: TimeInterval = 7 * 86400
                guard date <= now.addingTimeInterval(60), date >= now.addingTimeInterval(-63 * 86400),
                      renewal > date, renewal.addingTimeInterval(-duration) <= date else { continue }
                result.readings.append(StudioReading(account: "agent-runway:\(family):\(account)", date: date,
                    reset: renewal, duration: duration, remaining: 100 - used))
            }
        }
        var seen = Set<String>()
        result.readings = result.readings.sorted { $0.date < $1.date }.filter { seen.insert($0.id).inserted }
        return result
    }

    static func load(directory: URL, source: URL, now: Date) throws -> Self {
        let destination = directory.appendingPathComponent("imported-allowance-history.json")
        if FileManager.default.fileExists(atPath: destination.path) {
            return try JSONDecoder().decode(Self.self, from: Data(contentsOf: destination))
        }
        guard FileManager.default.fileExists(atPath: source.path) else { return Self() }
        let imported = try decode(Data(contentsOf: source), now: now)
        try JSONEncoder().encode(imported).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return imported
    }
}
