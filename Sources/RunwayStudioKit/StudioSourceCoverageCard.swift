import SwiftUI

/// Describes what the local event index can observe; no count implies absence of usage elsewhere.
struct StudioSourceCoverageCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Activity Coverage")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Label {
                Text("Claude Code: Local session logs are indexed when available.")
            } icon: {
                Image(systemName: "checkmark.circle").foregroundStyle(StudioStyle.mint)
            }
            Label {
                Text("Claude Chat and Desktop Chat: Usage is not available in the local session index.")
            } icon: {
                Image(systemName: "minus.circle").foregroundStyle(StudioStyle.muted)
            }
            Label {
                Text("Cowork: Local sandbox session logs are indexed when available.")
            } icon: {
                Image(systemName: "checkmark.circle").foregroundStyle(StudioStyle.mint)
            }
            Text("Unobserved activity is unknown, not zero. The source breakdown identifies known local paths. Other or conflicting sources remain unknown.")
                .font(.caption2).foregroundStyle(StudioStyle.muted)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioPanel()
    }
}
