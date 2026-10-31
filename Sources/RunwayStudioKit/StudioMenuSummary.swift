import Foundation

enum StudioSummaryRange: String, CaseIterable {
    case today = "Today", yesterday = "Yesterday", month = "30 Days"

    func keys(now: Date, calendar: Calendar = .current) -> Set<String> {
        let offsets = self == .today ? [0] : self == .yesterday ? [1] : Array(0..<30)
        return Set(offsets.compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now))
                .map { StudioDay.key($0, calendar: calendar) }
        })
    }
}

struct StudioSummaryValue: Identifiable {
    let id: String
    let name: String
    let tokens: Int?
    let cost: Double?
    let incomplete: Bool
    func value(cost: Bool) -> Double? { cost ? self.cost : tokens.map(Double.init) }

    static func build(snapshots: [StudioSnapshot], range: StudioSummaryRange, now: Date,
                      calendar: Calendar = .current) -> [Self] {
        let keys = range.keys(now: now, calendar: calendar)
        return ["claude", "codex"].compactMap { family in
            let cards = snapshots.filter { $0.family == family }
            // Tracker local-log history is shared by a provider's accounts: never sum duplicate histories.
            guard let card = cards.first(where: { $0.id == family }) ?? cards.first else { return nil }
            let history = card.usageHistory
            let days = history?.series.daily.filter { keys.contains($0.date) } ?? []
            let tokens = days.compactMap(\.totalTokens)
            let costs = days.compactMap(\.costUSD).filter { $0.isFinite && $0 >= 0 }
            let unpriced = (history?.unknownModelsByDay ?? [:]).contains { keys.contains($0.key) && !$0.value.isEmpty }
            let missing = days.contains { ($0.totalTokens ?? 0) > 0 && ($0.costUSD == nil || !($0.costUSD?.isFinite ?? false)) }
            return Self(id: family, name: family == "claude" ? "Claude" : "Codex",
                tokens: tokens.isEmpty ? nil : tokens.reduce(0, +),
                cost: costs.isEmpty ? nil : costs.reduce(0, +), incomplete: unpriced || missing)
        }
    }
}
