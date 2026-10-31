import Charts
import Runway
import SwiftUI

/// The daily surface: provider allowances first, local activity below, dashboard on demand.
struct StudioMenuPopover: View {
    let store: StudioStore
    let dashboard: () -> Void
    let alerts: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(StudioStyle.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runway Studio").font(.system(size: 15, weight: .semibold))
                    Text(store.refreshMessage ?? "Your allowances at a glance").font(.caption).foregroundStyle(StudioStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { store.requestManualRefresh() } label: {
                    Image(systemName: store.providerRefreshing ? "hourglass" : "arrow.clockwise")
                }.buttonStyle(.borderless).disabled(store.loading || store.manualRefreshing || store.providerRefreshing)
                    .accessibilityLabel("Refresh Provider Readings")
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.snapshots.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Waiting for provider readings", systemImage: "clock")
                            Text("Open the Runway tracker to connect Claude and Codex. Then quit the setup app to let Studio poll.")
                                .font(.caption).foregroundStyle(StudioStyle.muted)
                            Button("Runway Setup…") { store.openTracker() }
                        }.padding(16)
                    }
                    dashboardLink
                    if store.display.preferences.showSummary {
                        StudioMenuSummaryCard(snapshots: store.snapshots, now: store.now)
                    }
                    ForEach(store.snapshots) { snapshot in
                        StudioMenuAllowance(snapshot: snapshot, store: store)
                    }
                    if store.display.preferences.showMenuActivity { StudioMenuActivity(store: store) }
                    if let error = store.error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Circle().fill(store.connected ? StudioStyle.mint : .orange).frame(width: 5, height: 5)
                        Text(store.connected ? "Studio Polling Active" : "Studio Polling Paused")
                        Spacer()
                        Text(store.now.formatted(date: .omitted, time: .shortened))
                    }.font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
                    if !store.pollingSummary.isEmpty {
                        Text(store.pollingSummary).font(.caption2).foregroundStyle(StudioStyle.muted)
                    }
                }.padding(14)
            }
            Divider()
            HStack(spacing: 14) {
                Button { store.customizationPresented = true; dashboard() } label: { Label("Customize…", systemImage: "slider.horizontal.3") }
                    .accessibilityLabel("Customize Studio")
                Button(action: alerts) { Label("Alerts & Report", systemImage: "bell") }
                Spacer()
                Button("Quit", action: quit)
            }.font(.caption).buttonStyle(.borderless).padding(16)
        }
        .frame(width: 440)
        .frame(maxHeight: .infinity)
        .background(StudioStyle.background)
        .preferredColorScheme(.dark)
    }

    private var dashboardLink: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "slider.horizontal.3").foregroundStyle(StudioStyle.mint).padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                Text("Make It Your Studio").font(.system(size: 14, weight: .semibold))
                Text("See projects, agents, models and activity in your full dashboard.")
                    .font(.caption).foregroundStyle(StudioStyle.muted)
                Button("Open Dashboard", action: dashboard)
                    .buttonStyle(.bordered).tint(StudioStyle.mint).font(.caption.weight(.medium))
            }
            Spacer(minLength: 0)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: 14))
    }

}

private struct StudioMenuAllowance: View {
    let snapshot: StudioSnapshot
    let store: StudioStore
    @State private var expanded = false
    @State private var copied = false
    private var accent: Color { StudioStyle.accent(snapshot) }
    private var stale: Bool { store.isStale(snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                providerIcon
                Text(snapshot.displayName).font(.system(size: 15, weight: .semibold))
                Spacer()
                if let plan = snapshot.plan {
                    Text(plan).font(.caption).foregroundStyle(StudioStyle.muted).lineLimit(1)
                }
            }.padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 16) {
                if let session = snapshot.session { limitRow(session) }
                if let weekly = snapshot.weekly { limitRow(weekly) }
                if store.display.preferences.showModelLimits {
                    ForEach(snapshot.modelLimits, id: \.label) { limitRow($0) }
                }
                if snapshot.lines.allSatisfy({ $0.type != "progress" }) {
                    Text("Allowance Unavailable").font(.caption).foregroundStyle(StudioStyle.muted)
                }
                if stale {
                    Label("Cached Reading · Retry Scheduled", systemImage: "clock")
                        .font(.caption2).foregroundStyle(.orange)
                }
                if let warning = snapshot.waitsForProvider ? snapshot.displayWarning : store.providerErrors[snapshot.id] ?? snapshot.displayWarning {
                    Text(warning).font(.caption2).foregroundStyle(.orange)
                }
                if expanded { details }
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(StudioStyle.muted).frame(maxWidth: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(expanded ? "Hide" : "Show") \(snapshot.displayName) Details")
            }.padding(16).background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            if let line = snapshot.weekly ?? snapshot.session {
                let pace = StudioPace(line: line, stale: stale, now: store.now)
                Label(pace.state.rawValue, systemImage: "circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(StudioStyle.status(pace.state))
                if let exhaustion = pace.exhaustion {
                    Text("May Run Out In \(StudioFormat.interval(exhaustion, now: store.now)) If Pace Holds")
                        .font(.caption2).foregroundStyle(.orange)
                } else if let projected = pace.projectedRemaining {
                    Text("~\(Int(projected.rounded()))% Spare At Reset If Pace Holds")
                        .font(.caption2).foregroundStyle(StudioStyle.muted)
                }
            }
            if let credits = snapshot.resets?.values?.first?.number {
                HStack {
                    Label("\(Int(credits)) Reset \(credits == 1 ? "Credit" : "Credits")", systemImage: "arrow.counterclockwise.circle")
                    Spacer()
                    if let expiry = snapshot.resets?.expiriesAt?.filter({ $0 > store.now }).min() {
                        Text("Expires In \(StudioFormat.interval(expiry, now: store.now))").foregroundStyle(.orange)
                    }
                }.font(.caption2).foregroundStyle(StudioStyle.muted)
            }
            HStack {
                Text("Updated \(snapshot.refreshedAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(StudioStyle.muted)
                Spacer()
                Button { store.shareText(snapshot); copied = true } label: {
                    Label(copied ? "Copied" : "Copy Snapshot", systemImage: copied ? "checkmark" : "doc.on.doc")
                }.buttonStyle(.borderless)
            }.font(.caption2)
        }
    }

    private var providerIcon: some View {
        let image = NSImage(size: NSSize(width: 19, height: 19))
        image.lockFocus()
        if let path = RunwayProviderArtwork.path(for: snapshot.family, in: CGRect(x: 0, y: 0, width: 19, height: 19)),
           let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor(accent).cgColor); context.addPath(path); context.fillPath()
        }
        image.unlockFocus()
        return Image(nsImage: image).accessibilityHidden(true)
    }

    private func limitRow(_ line: StudioLine) -> some View {
        let pending = line.resetsAt.map { $0 <= store.now } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            Text(line.label).font(.system(size: 13, weight: .semibold))
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.09)).overlay(alignment: .leading) {
                    Capsule().fill(stale ? StudioStyle.muted : accent)
                        .frame(width: geometry.size.width * (pending ? 0 : line.remaining ?? 0) / 100)
                }
            }.frame(height: 5).accessibilityHidden(true)
            HStack {
                Text(pending ? "Awaiting Reset" : line.remaining.map { "\(Int($0.rounded()))% Left" } ?? "Unavailable")
                    .monospacedDigit()
                Spacer()
                if let reset = line.resetsAt, !pending {
                    Text("Resets In \(StudioFormat.interval(reset, now: store.now))").foregroundStyle(StudioStyle.muted)
                }
            }.font(.caption)
        }
    }
}

private struct StudioMenuActivity: View {
    let store: StudioStore
    @State private var reports: [String: ActivityReport] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Local activity", systemImage: "chart.bar.xaxis").font(.caption.weight(.semibold))
                Spacer()
                Text("LAST 24 HOURS").font(.system(size: 9)).foregroundStyle(StudioStyle.muted)
            }
            ForEach(["claude", "codex"], id: \.self) { family in
                if let report = reports[family] {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(family == "claude" ? "Claude" : "Codex").font(.caption.weight(.medium))
                            Text("\(StudioFormat.tokens(report.totals.total)) tokens").font(.caption2)
                            Text("\(StudioFormat.tokens(report.totals.newOnly)) new").font(.system(size: 10))
                                .foregroundStyle(StudioStyle.muted)
                        }.frame(width: 104, alignment: .leading)
                        if report.buckets.isEmpty {
                            Text("No recorded activity").font(.caption2).foregroundStyle(StudioStyle.muted)
                                .frame(maxWidth: .infinity)
                        } else {
                            Chart(report.buckets) { bucket in
                                BarMark(x: .value("Hour", bucket.start, unit: .hour), y: .value("Tokens", bucket.tokens.total))
                                    .foregroundStyle(family == "claude" ? StudioStyle.mint : StudioStyle.violet)
                            }
                            .chartXScale(domain: store.now.addingTimeInterval(-86400)...store.now)
                            .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 42)
                            .accessibilityLabel("\(family) hourly token activity over the last 24 hours")
                        }
                    }
                }
            }
            Text(store.activityScanning && reports.isEmpty ? "Reading local logs…" : "All local accounts · totals include cached tokens")
                .font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
        }
        .padding(15).background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: 14))
        .task(id: store.activityRevision) {
            let interval = ActivityReport.interval(days: 1, now: store.now)
            reports = Dictionary(uniqueKeysWithValues: ["claude", "codex"].map { family in
                (family, ActivityReport.build(events: store.activityEvents, provider: family,
                    interval: interval, resolution: .hourly, grouping: .project))
            })
        }
    }
}
