import SwiftUI

/// Displays the existing schedule and cached provider timestamps; it never starts a check.
struct StudioPollingHealthCard: View {
    let store: StudioStore
    let family: String

    private var cards: [StudioSnapshot] { store.snapshots.filter { $0.family == family } }
    private var record: StudioPollRecord? { store.polling.state.records[family] }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("\(family.capitalized) Refresh Health", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Spacer()
                    Text(status).font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(cards) { card in
                        detail("\(card.displayName) Reading", "\(store.isStale(card) ? "Cached" : "Fresh") · \(card.refreshedAt.formatted(date: .abbreviated, time: .standard))")
                    }
                    if cards.isEmpty { detail("Last Provider Reading", "None available") }
                    detail("Latest Recorded Check", record?.lastAttempt.map {
                        $0.formatted(date: .abbreviated, time: .shortened)
                    } ?? "None recorded")
                    detail("Next Permitted Check", nextCheck(now: timeline.date))
                }
                .font(.caption)
                Text("The recorded check can be seeded from a recent cached reading when Studio starts.")
                    .font(.caption2).foregroundStyle(StudioStyle.muted)
                if let error = store.polling.errors[family] {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                if let record, record.consecutiveFailures > 0 {
                    Text("\(record.consecutiveFailures) consecutive unsuccessful check\(record.consecutiveFailures == 1 ? "" : "s"); the retry schedule is preserved.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let deadline = record?.providerRetryAfter, deadline > timeline.date {
                    Text("Provider retry deadline: \(deadline.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let reason = store.polling.conflict ?? store.polling.problem {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                } else if !store.polling.active {
                    Text("Provider polling is paused.").font(.caption).foregroundStyle(.orange)
                }
                if let error = store.error, error != store.polling.conflict, error != store.polling.problem {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioPanel()
        }
    }

    private var status: String {
        if !store.polling.active { return "Paused" }
        if store.polling.isPolling { return "Checking Schedule" }
        if (record?.consecutiveFailures ?? 0) > 0 { return "Retry Backoff" }
        return "Scheduled"
    }

    private var statusColor: Color {
        !store.polling.active || (record?.consecutiveFailures ?? 0) > 0 ? .orange : StudioStyle.mint
    }

    private func nextCheck(now: Date) -> String {
        guard let next = store.polling.nextAttempt(family: family) else { return "No cooldown recorded" }
        let date = next.formatted(date: .abbreviated, time: .shortened)
        guard next > now else { return "Permitted now · \(date)" }
        let seconds = Int(ceil(next.timeIntervalSince(now)))
        let remaining = seconds >= 3600 ? "\(seconds / 3600)h \((seconds % 3600) / 60)m" : "\(seconds / 60)m \(seconds % 60)s"
        return "In \(remaining) · \(date)"
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(StudioStyle.muted)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
