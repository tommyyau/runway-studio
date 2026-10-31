import Foundation

struct StudioMenuEntry: Identifiable, Equatable {
    var id: String
    var family: String
    var name: String
    var weekly: Double?
    var session: Double?
    var stale: Bool
    var awaitingReset: Bool
    var primary: Double? { weekly ?? session }
    var cells: Int { Self.cellCount(primary) }
    var level: StudioAllowanceLevel { .remaining(primary) }
    var summary: String {
        if awaitingReset, primary == nil { return "\(name): awaiting reset confirmation" }
        var parts: [String] = []
        if let session { parts.append("session \(Int(session.rounded()))% left") }
        if let weekly { parts.append("weekly \(Int(weekly.rounded()))% left") }
        return name + ": " + (parts.isEmpty ? "reading unavailable" : parts.joined(separator: ", "))
            + (stale ? " (cached reading)" : "")
    }

    static func cellCount(_ remaining: Double?) -> Int {
        guard let remaining, remaining.isFinite, remaining > 0 else { return 0 }
        if remaining >= 100 { return 5 }
        return max(1, min(4, Int((remaining / 20).rounded())))
    }

    static func make(snapshots: [StudioSnapshot], staleIDs: Set<String>, now: Date, preferredAccounts: [String: String] = [:]) -> [Self] {
        ["claude", "codex"].compactMap { family in
            let cards = snapshots.filter { $0.family == family }
            guard let snapshot = cards.first(where: { $0.id == preferredAccounts[family] })
                ?? cards.first(where: { $0.id == family }) ?? cards.first else { return nil }
            let stale = staleIDs.contains(snapshot.id) || snapshot.isStale(now: now)
            func value(_ line: StudioLine?) -> Double? {
                guard let line else { return nil }
                if let reset = line.resetsAt, reset <= now { return nil }
                return line.remaining
            }
            return Self(id: snapshot.id, family: family, name: snapshot.displayName,
                weekly: value(snapshot.weekly), session: value(snapshot.session), stale: stale,
                awaitingReset: [snapshot.weekly, snapshot.session].compactMap { $0?.resetsAt }.contains { $0 <= now })
        }
    }
}

enum StudioAllowanceLevel {
    case unavailable, green, orange, red

    static func remaining(_ percentage: Double?) -> Self {
        guard let percentage, percentage.isFinite else { return .unavailable }
        if percentage <= 10 { return .red }
        if percentage <= 30 { return .orange }
        return .green
    }
}
