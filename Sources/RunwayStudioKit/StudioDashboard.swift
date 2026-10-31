import AppKit
import SwiftUI

struct StudioDashboard: View {
    @State var store: StudioStore
    var exporting = false
    private var days: Int { store.display.preferences.activityDays }
    private var showCost: Bool { store.display.preferences.showAPIValue }
    @State private var selectedProvider = "all"

    private var visible: [StudioSnapshot] {
        store.snapshots.filter { selectedProvider == "all" || $0.family == selectedProvider }
    }

    private var activitySnapshots: [StudioSnapshot] {
        ["claude", "codex"].compactMap { family in
            let cards = visible.filter { $0.family == family }
            return cards.first { $0.id == family } ?? cards.first
        }
    }

    var body: some View {
        @Bindable var boundStore = store
        VStack(spacing: 0) {
            header
            if exporting { dashboardContent } else { ScrollView { dashboardContent } }
        }
        .foregroundStyle(.white)
        .background(StudioStyle.background)
        .preferredColorScheme(.dark)
        .frame(minWidth: 880, minHeight: 660)
        .sheet(isPresented: $boundStore.customizationPresented) { StudioCustomize(store: store) }
    }

    private var dashboardContent: some View {
                VStack(alignment: .leading, spacing: 22) {
                    intro
                    if store.display.preferences.showServiceStatus {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 20)], spacing: 20) {
                        ForEach(Array(Set(visible.map(\.family))).sorted(), id: \.self) { provider in
                            StudioServiceStatusCard(store: store.serviceStatus, provider: provider)
                        }
                    }
                    }
                    if let error = store.display.error { notice(error) }
                    if let message = store.refreshMessage { notice(message) }
                    if let error = store.error { notice(error) }
                    if let error = store.alerts.storageError { notice(error) }
                    if let error = store.alerts.deliveryError { notice(error) }
                    if !store.connected {
                        notice("Studio polling is paused. Check the notice above for details.")
                    }
                    if store.snapshots.isEmpty {
                        ContentUnavailableView("Waiting For Studio Data", systemImage: "antenna.radiowaves.left.and.right",
                            description: Text("Sign in through Claude Code or Codex on this Mac. Studio reads those sign-ins directly."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 20, alignment: .top)], alignment: .leading, spacing: 20) {
                        ForEach(visible) { snapshot in
                            StudioAllowanceCard(snapshot: snapshot, store: store)
                        }
                    }
                    if !store.pollingSummary.isEmpty {
                        Text(store.pollingSummary).font(.caption).foregroundStyle(StudioStyle.muted)
                    }
                    if store.display.preferences.showRefreshHealth {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 20)], spacing: 20) {
                            ForEach(Array(Set(visible.map(\.family))).sorted(), id: \.self) { family in
                                StudioPollingHealthCard(store: store, family: family)
                            }
                        }
                    }
                    activityControls
                    if !showCost, selectedProvider != "codex" { StudioSourceCoverageCard() }
                    if showCost {
                        ForEach(activitySnapshots) { snapshot in
                            StudioActivityCard(snapshot: snapshot, days: days, showCost: true, now: store.now)
                        }
                    } else {
                        ForEach(Array(Set(visible.map(\.family))).sorted(), id: \.self) { provider in
                            StudioEventActivityCard(provider: provider, store: store, days: days)
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                        Text("Local data · Account allowance and this Mac's tokens are separate measurements.")
                    }
                    .font(.caption).foregroundStyle(StudioStyle.muted)
                }
                .padding(30)
                .frame(maxWidth: 1400)
                .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.system(size: 24)).foregroundStyle(StudioStyle.mint)
            Text("RUNWAY").font(.system(size: 14, weight: .heavy, design: .rounded)).tracking(3)
            Text("STUDIO").font(.system(size: 10, weight: .semibold)).tracking(2)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.white.opacity(0.08), in: Capsule())
            Spacer()
            Circle().fill(store.connected ? StudioStyle.mint : .orange).frame(width: 6, height: 6)
            Text(store.connected ? "Studio Polling Active" : "Polling Paused")
                .font(.caption).foregroundStyle(StudioStyle.muted)
            Button("Customize…") { store.customizationPresented = true }.buttonStyle(.bordered)
            Button("Alerts & Report") { StudioWindows.openAlerts?() }.buttonStyle(.bordered)
            Menu {
                ForEach(store.snapshots) { snapshot in
                    Button(snapshot.displayName) { StudioWindows.openMonitor?(snapshot.id) }
                }
            } label: { Label("Monitor", systemImage: "pip") }
                .fixedSize().disabled(store.snapshots.isEmpty)
            Button { store.requestManualRefresh() } label: { Image(systemName: store.providerRefreshing ? "hourglass" : "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(store.loading || store.manualRefreshing || store.providerRefreshing)
                .accessibilityLabel("Refresh Provider Readings")
            Button("Accounts…") { store.openAccounts() }.buttonStyle(.bordered)
        }
        .padding(.horizontal, 30).padding(.vertical, 17)
        .background(StudioStyle.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }

    private var intro: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Your AI, in view.").font(.system(size: 33, weight: .semibold, design: .rounded))
                Text("Allowance, pace and activity. One place to decide what to do next.")
                    .font(.system(size: 13)).foregroundStyle(StudioStyle.muted)
            }
            Spacer()
            Picker("Provider", selection: $selectedProvider) {
                Text("All").tag("all")
                Text("Claude").tag("claude")
                Text("Codex").tag("codex")
            }.pickerStyle(.segmented).labelsHidden().frame(width: 205)
        }
    }

    private var activityControls: some View {
        @Bindable var display = store.display
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Activity On This Mac").font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(showCost ? "Daily API-rate estimates from the tracker." : "Hourly sessions, projects and agents. Separate from account allowance.")
                    .font(.caption).foregroundStyle(StudioStyle.muted)
            }
            Spacer()
            Picker("Measure", selection: $display.preferences.showAPIValue) {
                Text("Tokens").tag(false); Text("API Value").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 155)
            Picker("Activity Range", selection: $display.preferences.activityDays) {
                Text(showCost ? "Today" : "24H").tag(1); Text("7D").tag(7); Text("14D").tag(14); Text("30D").tag(30)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 215)
        }.padding(.top, 8)
    }

    private func notice(_ message: String) -> some View {
        Label(message, systemImage: "info.circle")
            .font(.callout).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
