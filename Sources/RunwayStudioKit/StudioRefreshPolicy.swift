import Foundation

struct StudioRefreshPlan {
    let requests: [String]
    let waitingFamilies: [String]

    init(visible: [StudioSnapshot], allCached: [StudioSnapshot]) {
        let families = ["claude", "codex"].filter { family in visible.contains { $0.family == family } }
        let waiting = families.filter { family in allCached.contains { $0.family == family && $0.waitsForProvider } }
        waitingFamilies = waiting
        requests = families.filter { !waiting.contains($0) }.flatMap { family -> [String] in
            let cards = visible.filter { $0.family == family }
            // The signed CLI treats a bare ID as a family selector. Run it once, never once per card.
            return cards.contains { $0.id == family } ? [family] : cards.map(\.id).sorted()
        }
    }

    static func confirmsNewReading(previous: Date?, reported: Date, started: Date) -> Bool {
        reported >= started.addingTimeInterval(-1) && previous.map { reported > $0 } != false
    }

    static func cacheHasReportedReadings(_ snapshots: [StudioSnapshot], reported: [String: Date]) -> Bool {
        reported.allSatisfy { id, date in
            snapshots.contains { $0.id == id && $0.refreshedAt >= date.addingTimeInterval(-1) }
        }
    }
}
