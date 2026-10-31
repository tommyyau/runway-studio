import Foundation

struct StudioReading: Codable, Identifiable, Equatable {
    var account: String
    var date: Date
    var reset: Date
    var duration: TimeInterval
    var remaining: Double
    var id: String { "\(account):\(date.timeIntervalSince1970)" }
    var start: Date { reset.addingTimeInterval(-duration) }
}

struct StudioArchive: Codable {
    var readings: [StudioReading] = []

    mutating func record(_ snapshot: StudioSnapshot, identity: String?, now: Date) {
        // An unnamed account cannot safely inherit or create historical readings.
        guard let identity, !identity.isEmpty, !snapshot.isStale(now: now), snapshot.loginRequired != true,
              snapshot.warning == nil, let line = snapshot.weekly, let remaining = line.remaining,
              let reset = line.resetsAt, let duration = line.duration,
              reset > snapshot.refreshedAt, reset.addingTimeInterval(-duration) <= snapshot.refreshedAt else { return }
        let account = snapshot.providerID + ":" + identity
        guard !readings.contains(where: { $0.account == account && $0.date == snapshot.refreshedAt }) else { return }
        readings.append(StudioReading(account: account, date: snapshot.refreshedAt,
                                      reset: reset, duration: duration, remaining: remaining))
        readings.removeAll { $0.date < now.addingTimeInterval(-63 * 86400) }
        readings.sort { $0.date < $1.date }
    }

    func current(account: String, reset: Date) -> [StudioReading] {
        // Provider dates may differ by subsecond rounding between requests.
        readings.filter { $0.account == account && abs($0.reset.timeIntervalSince(reset)) < 2 }
    }

    /// Only windows with actual readings are navigable. Never infer missing weeks.
    func windows(account: String) -> [StudioWindow] {
        var result: [StudioWindow] = []
        for reading in readings.filter({ $0.account == account }).sorted(by: { $0.date < $1.date }) {
            if let index = result.firstIndex(where: { abs($0.reset.timeIntervalSince(reading.reset)) < 2 }) {
                result[index].readings.append(reading)
            } else {
                result.append(StudioWindow(reset: reading.reset, duration: reading.duration, readings: [reading]))
            }
        }
        return result.sorted { $0.reset < $1.reset }
    }

    func completed(account: String, now: Date) -> [StudioReading] {
        Array(windows(account: account).filter { $0.reset < now }
            .compactMap { $0.readings.last }.suffix(8))
    }
}

struct StudioWindow: Identifiable {
    let reset: Date
    let duration: TimeInterval
    var readings: [StudioReading]
    var id: Date { reset }
    var start: Date { reset.addingTimeInterval(-duration) }
}

struct StudioGlidePoint: Identifiable {
    let reading: StudioReading
    let segment: Int
    var id: String { reading.id }

    static func segments(_ readings: [StudioReading]) -> [Self] {
        var lastDate: Date?
        var segment = 0
        return readings.map { reading in
            if let lastDate, reading.date.timeIntervalSince(lastDate) > 1200 { segment += 1 }
            lastDate = reading.date
            return Self(reading: reading, segment: segment)
        }
    }
}

struct StudioPace {
    enum State: String { case available = "Ready", ahead = "Room To Spare", steady = "On Pace", tight = "Getting Tight", exhausted = "Limit Reached", pending = "Awaiting Reset", stale = "Cached Reading" }
    var state: State
    var projectedRemaining: Double?
    var exhaustion: Date?

    init(line: StudioLine, stale: Bool, now: Date) {
        state = .available
        if stale { state = .stale; return }
        guard let reset = line.resetsAt else { return }
        guard reset > now else { state = .pending; return }
        guard let remaining = line.remaining else { return }
        if remaining <= 0 { state = .exhausted; return }
        guard let duration = line.duration else { return }
        let elapsed = now.timeIntervalSince(reset.addingTimeInterval(-duration))
        let used = 100 - remaining
        guard elapsed >= max(60, duration * 0.01), used >= 5 else { return }
        let projectedUsed = used / elapsed * duration
        projectedRemaining = max(0, 100 - projectedUsed)
        if projectedUsed > 100 {
            state = .tight
            exhaustion = now.addingTimeInterval(remaining / (used / elapsed))
        } else if projectedUsed > 90 { state = .steady }
        else { state = .ahead }
    }
}
