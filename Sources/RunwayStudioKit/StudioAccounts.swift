import SwiftUI

struct StudioAccounts: View {
    let store: StudioStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Studio Accounts").font(.title2.weight(.semibold))
                Text("Studio reads your existing Claude and Codex sign-ins directly using its bundled provider engine. No other Runway app or helper is needed.")
                    .font(.callout).foregroundStyle(StudioStyle.muted)
                ForEach(["claude", "codex"], id: \.self) { family in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(family == "claude" ? "Claude" : "Codex").font(.headline)
                        Text(family == "claude" ? "Sign in through Claude Code on this Mac. If a login expires, use Claude Code’s normal sign-in flow and let Studio check again." : "Sign in through Codex on this Mac. Studio uses the existing local auth files or authorized Keychain entry.")
                            .font(.callout).foregroundStyle(StudioStyle.muted)
                        ForEach(store.snapshots.filter { $0.family == family }) { card in
                            Text("\(card.displayName): \(store.isStale(card) ? "Cached Or Awaiting Connection" : "Connected")")
                            if let warning = card.displayWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
                        }
                        if let error = store.polling.errors[family] { Text(error).font(.caption).foregroundStyle(.orange) }
                    }.studioPanel()
                }
                Text("Background checks never request a Keychain password. If macOS blocks a protected credential, Studio reports it instead of repeatedly prompting. No App Management or administrator permission is required.")
                    .font(.caption).foregroundStyle(StudioStyle.muted)
                Button("Check Scheduled Connections") { store.requestManualRefresh() }
                    .disabled(store.loading || store.manualRefreshing || store.providerRefreshing)
                Text(store.pollingSummary).font(.caption).foregroundStyle(StudioStyle.muted)
                if let error = store.error { Text(error).foregroundStyle(.orange).font(.caption) }
            }.padding(24)
        }.frame(minWidth: 560, minHeight: 500)
            .background(StudioStyle.background).preferredColorScheme(.dark)
    }
}
