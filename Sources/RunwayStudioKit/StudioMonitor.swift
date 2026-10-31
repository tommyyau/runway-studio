import AppKit
import Charts
import SwiftUI

@MainActor enum StudioWindows {
    static var openMonitor: ((String) -> Void)?
    static var openAlerts: (() -> Void)?
}

struct StudioMonitor: View {
    let providerID: String
    @State var store: StudioStore
    let setFloating: (Bool) -> Void
    @State private var floating = true
    @State private var days = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Monitor", systemImage: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle(isOn: $floating) { Image(systemName: floating ? "pin.fill" : "pin") }
                    .toggleStyle(.button).buttonStyle(.borderless)
                    .accessibilityLabel("Keep Monitor Above Other Windows")
                    .onChange(of: floating) { setFloating(floating) }
            }.padding(16).background(StudioStyle.panel)
            ScrollView {
                VStack(spacing: 14) {
                    if let snapshot = store.snapshots.first(where: { $0.providerID == providerID }) {
                        StudioAllowanceCard(snapshot: snapshot, store: store)
                        activity(snapshot)
                    } else {
                        ContentUnavailableView("Account Unavailable", systemImage: "person.crop.circle.badge.questionmark",
                            description: Text("Check the account in Runway."))
                    }
                }.padding(14)
            }
        }
        .background(StudioStyle.background).foregroundStyle(.white).preferredColorScheme(.dark)
        .frame(minWidth: 410, minHeight: 400)
    }

    private func activity(_ snapshot: StudioSnapshot) -> some View {
        let report = ActivityReport.build(events: store.activityEvents, provider: snapshot.family,
            interval: ActivityReport.interval(days: days, now: store.activityUpdatedAt ?? store.now),
            resolution: days == 1 ? .hourly : .daily, grouping: .project)
        let points = report.buckets
        let total = report.totals.total
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(StudioFormat.tokens(total)) tokens").font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Days", selection: $days) {
                    Text("24H").tag(1); Text("7D").tag(7); Text("30D").tag(30)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 140)
            }
            Chart(points) { point in
                    BarMark(x: .value("Time", point.start, unit: days == 1 ? .hour : .day), y: .value("Tokens", point.tokens.total))
                        .foregroundStyle(StudioStyle.accent(snapshot).gradient).cornerRadius(2)
            }.frame(height: 85).chartYAxis(.hidden)
                .chartXAxis { AxisMarks(values: .stride(by: days == 1 ? .hour : .day, count: days == 1 ? 6 : days > 7 ? 7 : 2)) { _ in
                    AxisValueLabel(format: days == 1 ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                } }
            Text(store.activityScanning ? "Indexing local sessions…" : "Native logs on this Mac · All accounts · Includes cache")
                .font(.caption2).foregroundStyle(StudioStyle.muted)
        }.studioPanel()
    }
}
