import Charts
import SwiftUI

struct StudioAllowanceCard: View {
    let snapshot: StudioSnapshot
    let store: StudioStore
    @State private var copied = false
    @State private var selectedWindow: Date?
    private var accent: Color { StudioStyle.accent(snapshot) }
    private var stale: Bool { store.isStale(snapshot) }
    private var now: Date { store.now }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(snapshot.displayName).font(.system(size: 19, weight: .semibold, design: .rounded))
                Spacer()
                if let plan = snapshot.plan {
                    Text(plan).font(.caption).foregroundStyle(StudioStyle.muted)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.05), in: Capsule())
                }
                Button {
                    store.shareText(snapshot); copied = true
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.borderless).accessibilityLabel("Copy \(snapshot.displayName) Allowance Summary")
            }
            if let weekly = snapshot.weekly, let remaining = weekly.remaining {
                let pace = StudioPace(line: weekly, stale: stale, now: now)
                HStack(spacing: 22) {
                    gauge(remaining)
                    VStack(alignment: .leading, spacing: 9) {
                        Label(pace.state.rawValue, systemImage: pace.exhaustion == nil ? "circle.fill" : "flame.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StudioStyle.status(pace.state))
                        if let reset = weekly.resetsAt {
                            Text(reset <= now ? "Waiting For Provider" : "Resets In \(StudioFormat.interval(reset, now: now))")
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                            Text(reset.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                                .font(.caption).foregroundStyle(StudioStyle.muted)
                        }
                        if let date = pace.exhaustion {
                            Text("At this pace: limit \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                                .font(.caption).foregroundStyle(.orange)
                        } else if let projected = pace.projectedRemaining {
                            Text("~\(Int(projected.rounded()))% spare at reset, if pace holds")
                                .font(.caption).foregroundStyle(StudioStyle.muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider().overlay(.white.opacity(0.03))
                StudioGlidePath(snapshot: snapshot, store: store, accent: accent, selectedWindow: $selectedWindow)
                if let session = snapshot.session, let left = session.remaining {
                    limitRow("Session", left: left, reset: session.resetsAt)
                }
                ForEach(snapshot.modelLimits, id: \.label) { line in
                    if let left = line.remaining { limitRow(line.label, left: left, reset: line.resetsAt) }
                }
                if let resets = snapshot.resets, let count = resets.values?.first?.number {
                    HStack {
                        Label("Reset Credits", systemImage: "arrow.counterclockwise.circle")
                        Spacer()
                        Text("\(Int(count)) available").monospacedDigit()
                    }.font(.caption).foregroundStyle(StudioStyle.muted)
                    if let expiry = resets.expiriesAt?.filter({ $0 > now }).min() {
                        Text("Next credit expires \(expiry.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
                completedWeeks
            } else {
                Label("Weekly Allowance Unavailable", systemImage: "questionmark.circle")
                    .foregroundStyle(StudioStyle.muted).frame(height: 180)
            }
            if let warning = snapshot.waitsForProvider ? snapshot.displayWarning : store.providerErrors[snapshot.providerID] ?? snapshot.displayWarning {
                Text(warning).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(stale ? "CACHED READING" : "PROVIDER READING")
                Spacer()
                Text(snapshot.refreshedAt.formatted(date: .omitted, time: .shortened))
            }.font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(StudioStyle.muted)
        }
        .studioPanel()
    }

    private func gauge(_ remaining: Double) -> some View {
        ZStack {
            Circle().stroke(accent.opacity(0.1), lineWidth: 11)
            Circle().trim(from: 0, to: remaining / 100)
                .stroke(AngularGradient(colors: [accent.opacity(0.5), accent], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int(remaining.rounded()))%")
                    .font(.system(size: 35, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("CURRENT WEEK LEFT").font(.system(size: 9, weight: .medium)).tracking(1.3)
                    .foregroundStyle(StudioStyle.muted)
            }
        }.frame(width: 123, height: 123).padding(6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int(remaining.rounded())) percent of weekly allowance remaining")
    }

    private func limitRow(_ title: String, left: Double, reset: Date?) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(left.rounded()))% left").monospacedDigit()
                if let reset {
                    Text(reset <= now ? "Awaiting Reset" : "· \(StudioFormat.interval(reset, now: now))")
                        .foregroundStyle(StudioStyle.muted)
                }
            }.font(.caption)
            GeometryReader { p in
                Capsule().fill(.white.opacity(0.06))
                    .overlay(alignment: .leading) {
                        Capsule().fill(left <= 10 ? Color.orange : accent.opacity(0.8))
                            .frame(width: p.size.width * left / 100)
                    }
            }.frame(height: 4)
        }
    }

    @ViewBuilder private var completedWeeks: some View {
        if let account = store.account(for: snapshot) {
            let weeks = store.archive.completed(account: account, now: now)
            if !weeks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Past Windows · Last Observed Use").font(.caption).foregroundStyle(StudioStyle.muted)
                    Chart(weeks) { week in
                        BarMark(x: .value("Reset", week.reset, unit: .day), y: .value("Used", 100 - week.remaining))
                            .foregroundStyle(accent.opacity(0.65))
                    }.chartYScale(domain: 0...100).frame(height: 55)
                    Text("Incomplete windows are lower bounds. Unobserved weeks stay absent.")
                        .font(.caption2).foregroundStyle(StudioStyle.muted)
                }
            }
        }
    }
}

private struct StudioGlidePath: View {
    let snapshot: StudioSnapshot
    let store: StudioStore
    let accent: Color
    @Binding var selectedWindow: Date?

    var body: some View {
        if let line = snapshot.weekly, let reset = line.resetsAt, let duration = line.duration {
            let windows = store.account(for: snapshot).map { store.archive.windows(account: $0) } ?? []
            let selected = selectedWindow.flatMap { date in windows.first { $0.reset == date } }
            let shownReset = selected?.reset ?? reset
            let start = selected?.start ?? reset.addingTimeInterval(-duration)
            let points = selected?.readings ?? (store.account(for: snapshot).map { store.archive.current(account: $0, reset: reset) } ?? [])
            let previous = windows.last { $0.reset < shownReset.addingTimeInterval(-2) }
            let next = windows.first { $0.reset > shownReset.addingTimeInterval(2) && $0.reset < reset.addingTimeInterval(-2) }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("WEEKLY GLIDE PATH").font(.system(size: 10, weight: .semibold)).tracking(1.3)
                    Spacer()
                    Button { selectedWindow = previous?.reset } label: { Image(systemName: "chevron.left") }
                        .disabled(previous == nil).buttonStyle(.borderless).accessibilityLabel("Previous Observed Window")
                    Text(selected == nil ? "Current" : shownReset.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundStyle(StudioStyle.muted)
                    Button { selectedWindow = next?.reset } label: { Image(systemName: "chevron.right") }
                        .disabled(selected == nil).buttonStyle(.borderless).accessibilityLabel("Next Observed Window")
                    StudioImageShareControl(image: StudioShareImage(
                        title: "\(snapshot.displayName) · Allowance",
                        interval: "\(start.formatted(date: .abbreviated, time: .shortened)) – \(shownReset.formatted(date: .abbreviated, time: .shortened))",
                        value: points.last.map { "\(Int($0.remaining.rounded()))% left at last reading" } ?? "No recorded reading",
                        note: "Provider allowance readings for this account. Only observed readings are shown; gaps do not imply zero usage.",
                        bars: points.map { StudioShareBar(date: $0.date, value: $0.remaining) }, accent: accent))
                    Text("-- Even pace").font(.caption2).foregroundStyle(StudioStyle.muted)
                }
                Chart {
                    ForEach([start, shownReset], id: \.self) { date in
                        LineMark(x: .value("Date", date), y: .value("Allowance Left", date == start ? 100.0 : 0),
                                 series: .value("Line", "Even Pace"))
                            .foregroundStyle(.white.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 5]))
                    }
                    ForEach(StudioGlidePoint.segments(points)) { plotted in
                        let point = plotted.reading
                        LineMark(x: .value("Date", point.date), y: .value("Allowance Left", point.remaining),
                                 series: .value("Line", "Observed \(plotted.segment)"))
                            .foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Date", point.date), y: .value("Allowance Left", point.remaining))
                            .foregroundStyle(accent).symbolSize(points.count < 4 ? 24 : 4)
                    }
                    if store.now >= start, store.now <= shownReset {
                        RuleMark(x: .value("Now", store.now))
                            .foregroundStyle(.white.opacity(0.15)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    }
                }
                .chartXScale(domain: start...shownReset).chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.04))
                        AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%").foregroundStyle(StudioStyle.muted) } }
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
                .frame(height: 116)
                Text(points.isEmpty ? "No recorded reading in this window." : points.count == 1 ? "One recorded reading in this window." : "Recorded allowance · gaps mark periods without observations")
                    .font(.caption2).foregroundStyle(StudioStyle.muted)
            }
        }
    }
}
