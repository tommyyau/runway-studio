import SwiftUI

struct StudioServiceStatusCard: View {
    let store: StudioServiceStatusStore
    let provider: String
    private var status: StudioServiceStatus? { store.statuses[provider] }

    private var title: String { provider == "claude" ? "Claude" : "OpenAI" }
    private var color: Color {
        guard let status, !status.isStale else { return StudioStyle.muted }
        switch status.indicator {
        case "none": return StudioStyle.mint
        case "minor": return .orange
        case "major", "critical": return .red
        default: return StudioStyle.muted
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(title) Service Status").font(.caption.weight(.semibold))
                if let status {
                    Text(status.isStale ? "Last known: \(status.description) · Update failed" : status.description)
                        .font(.caption).foregroundStyle(StudioStyle.muted)
                    Text("Checked \(status.checkedAt.formatted(date: .abbreviated, time: .shortened)) · Provider-wide")
                        .font(.caption2).foregroundStyle(StudioStyle.muted)
                } else {
                    Text(store.checked ? "Unavailable · Could not check public status" : "Checking public status…")
                        .font(.caption).foregroundStyle(StudioStyle.muted)
                }
            }
            Spacer()
            Link("Status Page", destination: URL(string: provider == "claude" ? "https://status.claude.com/" : "https://status.openai.com/")!)
                .font(.caption)
        }
        .studioPanel()
    }
}
