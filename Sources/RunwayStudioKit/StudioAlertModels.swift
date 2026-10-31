import Foundation

struct StudioDropRule: Codable, Equatable {
    var enabled = false
    var points = 10
    var minutes = 15
}

struct StudioAlertPreferences: Codable, Equatable {
    var enabled = true
    var lowAllowance = true
    var forecast = true
    var recovery = true
    var resetChanges = true
    var expiry = true
    var spare = false
    var morning = true
    var hour = 7
    var minute = 0
    var timeZoneID = "Europe/London"
    var claudeDrop = StudioDropRule()
    var codexDrop = StudioDropRule()
}

struct StudioAlertMeter: Codable, Equatable {
    var remaining: Double
    var reset: Date
    var duration: TimeInterval?
    var windowKey: String { String(Int(reset.timeIntervalSince1970.rounded())) }
    init?(_ line: StudioLine?) {
        guard let line, let remaining = line.remaining, let reset = line.resetsAt else { return nil }
        self.remaining = remaining; self.reset = reset; duration = line.duration
    }
    init(remaining: Double, reset: Date, duration: TimeInterval? = 604800) {
        self.remaining = remaining; self.reset = reset; self.duration = duration
    }
    func exhaustion(now: Date) -> Date? {
        guard let duration, duration > 0, remaining > 0, remaining <= 95, reset > now else { return nil }
        let elapsed = now.timeIntervalSince(reset.addingTimeInterval(-duration))
        guard elapsed >= max(60, duration * 0.01) else { return nil }
        let result = now.addingTimeInterval(remaining / ((100 - remaining) / elapsed))
        return result < reset ? result : nil
    }
}

struct StudioAlertObservation: Codable, Equatable {
    var account: String
    var cardID: String
    var name: String
    var family: String
    var fetchedAt: Date
    var weekly: StudioAlertMeter?
    var session: StudioAlertMeter?
    var credits: Int?
    var expiries: [Date]
    var fresh: Bool
    var blocked: Bool { [weekly, session].compactMap { $0 }.contains { $0.remaining <= 0 && $0.reset > fetchedAt } }
    var weeklySummary: String { weekly.map { "\(Int($0.remaining.rounded()))% weekly allowance left" } ?? "Weekly allowance unavailable" }
}

struct StudioAlertEvent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case low, forecast, recovery, reset, drop, spare, expiry, morning, test }
    var id: String
    var account: String
    var kind: Kind
    var title: String
    var body: String
    var createdAt: Date
}

struct StudioAlertAccountState: Codable, Equatable {
    struct Sample: Codable, Equatable { var date: Date; var remaining: Double }
    var previous: StudioAlertObservation
    var samples: [Sample] = []
    var dropActive = false
    var dropEpisode = 0
    var quietSince: Date?
    var unavailableSince: Date?
    var lastAlertAt: Date?
}

enum StudioAlertText {
    static func date(_ date: Date, timeZone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: timeZone) ?? .current
        formatter.dateFormat = "EEE d MMM 'at' HH:mm"
        return formatter.string(from: date)
    }
    static func morning(_ observations: [StudioAlertObservation], now: Date, preferences: StudioAlertPreferences) -> String {
        if observations.isEmpty { return "No account readings are available. Open Runway and check your connections." }
        return observations.map { observation in
            guard observation.fresh else {
                return "\(observation.name): reading unavailable (last update \(date(observation.fetchedAt, timeZone: preferences.timeZoneID)))."
            }
            var text = "\(observation.name): \(observation.weeklySummary)"
            if let weekly = observation.weekly {
                text += weekly.reset <= now ? " · awaiting reset confirmation" : " · resets \(date(weekly.reset, timeZone: preferences.timeZoneID))"
                if observation.blocked { text += " · usage limit reached" }
                else if let exhaustion = weekly.exhaustion(now: now) {
                    text += "\nAt the average pace so far, may reach the limit \(date(exhaustion, timeZone: preferences.timeZoneID))."
                }
            }
            if let next = observation.expiries.filter({ $0 > now }).min() {
                text += "\nNext reset credit expires \(date(next, timeZone: preferences.timeZoneID))."
            }
            return text
        }.joined(separator: "\n\n")
    }
}
