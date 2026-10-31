import Foundation

// Read-only projections of Runway's v9 snapshot cache. Unused cache fields are deliberately ignored.
struct StudioCache: Decodable {
    var snapshots: [String: StudioSnapshot]
    var producedByIdentityKeys: [String: String]

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date"))
            }
            return date
        }
        return try decoder.decode(Self.self, from: data)
    }
}

struct StudioSnapshot: Decodable, Identifiable {
    var providerID: String
    var displayName: String
    var plan: String?
    var refreshedAt: Date
    var lines: [StudioLine]
    var usageHistory: StudioUsageHistory?
    var warning: String?
    var loginRequired: Bool?
    var warningAction: String?
    var waitsForProvider: Bool {
        warningAction == "wait" || (warningAction == nil && warning?.contains("Updates blocked by Anthropic") == true)
    }
    var displayWarning: String? {
        waitsForProvider ? "Provider updates are temporarily blocked. Studio will retry automatically; the allowance shown is the last successful reading." : warning
    }
    var id: String { providerID }
    var family: String { providerID.components(separatedBy: "@").first ?? providerID }
    var weekly: StudioLine? { lines.first { $0.label == "Weekly" && $0.type == "progress" } }
    var session: StudioLine? { lines.first { $0.label == "Session" && $0.type == "progress" } }
    var resets: StudioLine? { lines.first { $0.label == "Rate Limit Resets" } }
    var modelLimits: [StudioLine] {
        lines.filter { $0.type == "progress" && $0.label != "Weekly" && $0.label != "Session" }
    }
    func isStale(now: Date) -> Bool { now.timeIntervalSince(refreshedAt) > 360 || refreshedAt > now.addingTimeInterval(60) }
}

struct StudioLine: Decodable {
    var type: String
    var label: String
    var used: Double?
    var limit: Double?
    var resetsAt: Date?
    var periodDurationMs: Int?
    var expiriesAt: [Date]?
    var values: [Value]?
    struct Value: Decodable { var number: Double; var label: String? }
    var remaining: Double? {
        guard let used, used.isFinite, let limit, limit.isFinite, limit > 0 else { return nil }
        return max(0, min(100, (1 - used / limit) * 100))
    }
    var duration: TimeInterval? {
        periodDurationMs.flatMap { $0 > 0 ? Double($0) / 1000 : nil }
    }
}

struct StudioUsageHistory: Decodable {
    var series: Series
    var modelUsage: ModelSeries?
    var unknownModelsByDay: [String: [String]]?
    struct Series: Decodable { var daily: [StudioDay] }
    struct ModelSeries: Decodable { var daily: [ModelDay] }
    struct ModelDay: Decodable { var date: String; var models: [StudioModel] }

    func days(count: Int, now: Date = Date(), calendar: Calendar = .current) -> [StudioDay] {
        let today = calendar.startOfDay(for: now)
        let byKey = Dictionary(series.daily.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = StudioDay.key(date, calendar: calendar)
            // A nil token count is a missing record, not an invented zero.
            return byKey[key] ?? StudioDay(date: key, totalTokens: nil, costUSD: nil)
        }
    }

    func models(in keys: Set<String>) -> [StudioModel] {
        var totals: [String: StudioModel] = [:]
        for day in modelUsage?.daily ?? [] where keys.contains(day.date) {
            for model in day.models {
                if var total = totals[model.model] {
                    total.totalTokens += model.totalTokens
                    total.costUSD = total.costUSD.flatMap { a in model.costUSD.map { a + $0 } }
                    totals[model.model] = total
                } else { totals[model.model] = model }
            }
        }
        return totals.values.sorted { $0.totalTokens > $1.totalTokens }
    }
}

struct StudioDay: Decodable, Identifiable {
    var date: String
    var totalTokens: Int?
    var costUSD: Double?
    var id: String { date }
    static func totalRecordedTokens(_ days: [Self]) -> Int? {
        let recorded = days.compactMap(\.totalTokens)
        return recorded.isEmpty ? nil : recorded.reduce(0, +)
    }
    var instant: Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: date) ?? .distantPast
    }
    static func key(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

struct StudioModel: Decodable, Identifiable {
    var model: String
    var totalTokens: Int
    var costUSD: Double?
    var id: String { model }
}

enum StudioFormat {
    static func tokens(_ value: Int) -> String {
        let n = Double(value)
        for (threshold, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "K")] where n >= threshold {
            return String(format: "%.1f%@", n / threshold, suffix)
        }
        return "\(value)"
    }
    static func money(_ value: Double) -> String { String(format: "$%.2f", value) }
    static func interval(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds >= 86400 { return "\(Int(seconds / 86400))d \(Int(seconds.truncatingRemainder(dividingBy: 86400) / 3600))h" }
        if seconds >= 3600 { return "\(Int(seconds / 3600))h \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60))m" }
        return "\(Int(seconds / 60))m"
    }
}
