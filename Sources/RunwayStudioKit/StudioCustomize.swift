import SwiftUI

struct StudioCustomize: View {
    let store: StudioStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var display = store.display
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Customize Studio").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Changes are saved on this Mac. Display choices do not change provider polling or alerts.")
                .font(.callout).foregroundStyle(StudioStyle.muted)
            Form {
                Section("Menu Bar") {
                    Picker("Snapshot Style", selection: $display.preferences.menuDisplay) {
                        ForEach(StudioMenuDisplay.allCases) { style in Text(style.title).tag(style) }
                    }
                    ForEach(["claude", "codex"], id: \.self) { family in
                        let cards = store.snapshots.filter { $0.family == family }
                        if cards.count > 1 {
                            Picker("\(family == "claude" ? "Claude" : "Codex") Account", selection: account(family)) {
                                Text("Automatic").tag("")
                                ForEach(cards) { card in Text("\(card.displayName) · \(card.id)").tag(card.id) }
                            }
                        }
                    }
                }
                Section("Compact Panel") {
                    Toggle("Summary Ring", isOn: $display.preferences.showSummary)
                    Toggle("Local Activity Sparklines", isOn: $display.preferences.showMenuActivity)
                    Toggle("Model Allowance Bars", isOn: $display.preferences.showModelLimits)
                }
                Section("Dashboard") {
                    Toggle("Public Service Status", isOn: $display.preferences.showServiceStatus)
                    Toggle("Refresh Health", isOn: $display.preferences.showRefreshHealth)
                    Picker("Activity Range", selection: $display.preferences.activityDays) {
                        Text("24 Hours / Today").tag(1); Text("7 Days").tag(7)
                        Text("14 Days").tag(14); Text("30 Days").tag(30)
                    }
                    Toggle("Show API Value Instead Of Tokens", isOn: $display.preferences.showAPIValue)
                }
            }.formStyle(.grouped)
            if let error = display.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(24).frame(width: 540, height: 600)
        .background(StudioStyle.background).preferredColorScheme(.dark)
    }

    private func account(_ family: String) -> Binding<String> {
        Binding(get: {
            let id = store.display.preferences.menuAccounts[family] ?? ""
            return store.snapshots.contains { $0.family == family && $0.id == id } ? id : ""
        }, set: { store.display.preferences.menuAccounts[family] = $0.isEmpty ? nil : $0 })
    }
}
