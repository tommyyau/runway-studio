import Charts
import SwiftUI

struct StudioEventActivityCard: View {
    let provider: String
    let store: StudioStore
    let days: Int
    @State private var resolution = ActivityResolution.hourly
    @State private var grouping = ActivityGrouping.project
    @State private var newOnly = false
    @State private var selection: ClosedRange<Date>?
    @State private var hoveredDate: Date?
    @State private var zoom: DateInterval?
    @State private var editingInterval = false
    @State private var customStart = Date()
    @State private var customEnd = Date()
    @State private var intervalError: String?
    @State private var report = ActivityReport(selectedInterval: DateInterval(start: Date(), duration: 0))
    private var accent: Color { provider == "claude" ? StudioStyle.mint : StudioStyle.violet }
    private var providerName: String { provider == "claude" ? "Claude" : "Codex" }
    private var anchor: Date { store.activityUpdatedAt ?? store.now }
    private var available: DateInterval { DateInterval(start: anchor.addingTimeInterval(-30 * 86400), end: anchor) }
    private var interval: DateInterval { zoom ?? ActivityReport.interval(days: days, now: anchor) }
    private var parts: [String] {
        if newOnly { return ["New Input", "Output"] }
        return ["Cached", "New Input", "Output"] + (report.buckets.contains { $0.tokens.unclassified > 0 } ? ["Unclassified"] : [])
    }
    private let amber = Color(red: 1, green: 0.66, blue: 0.32)
    private func partColor(_ part: String) -> Color {
        switch part {
        case "Cached": accent.opacity(0.38)
        case "New Input": accent
        case "Output": amber
        default: Color(red: 0.72, green: 0.66, blue: 0.88)
        }
    }
    private var hoveredBucket: ActivityBucket? {
        guard let hoveredDate else { return nil }
        return report.buckets.first { hoveredDate >= $0.start && hoveredDate < $0.end }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(providerName) · Local Sessions").font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                Text(StudioFormat.tokens(report.totals.value(newOnly: newOnly)))
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(newOnly ? "new tokens" : "tokens").font(.caption).foregroundStyle(StudioStyle.muted)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Bucket Size", selection: $resolution) {
                        ForEach(ActivityResolution.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 230)
                    Picker("Token Categories", selection: $newOnly) {
                        Text("All Tokens").tag(false); Text("New Only").tag(true)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 185)
                    Spacer()
                    Picker("Group Activity", selection: $grouping) {
                        ForEach(ActivityGrouping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 145)
                    StudioImageShareControl(image: shareImage)
                }
                HStack {
                    Button("Zoom To Selection") { zoomToSelection() }
                        .disabled(selection == nil)
                    Button("Reset Zoom") { zoom = nil; selection = nil; rebuild() }
                        .disabled(zoom == nil)
                    Button("Choose Interval…") {
                        customStart = interval.start; customEnd = interval.end
                        intervalError = nil; editingInterval.toggle()
                    }
                    if selection != nil { Button("Clear Selection") { selection = nil; intervalError = nil } }
                }.buttonStyle(.borderless).font(.caption)
                if !editingInterval, let intervalError { Text(intervalError).font(.caption).foregroundStyle(.orange) }
                if editingInterval {
                    HStack {
                        DatePicker("From", selection: $customStart, in: available.start...available.end,
                                   displayedComponents: [.date, .hourAndMinute])
                        DatePicker("To", selection: $customEnd, in: available.start...available.end,
                                   displayedComponents: [.date, .hourAndMinute])
                        Button("Apply") { applyCustomInterval() }
                        Button("Cancel") { editingInterval = false; intervalError = nil }
                    }.font(.caption)
                    if let intervalError { Text(intervalError).font(.caption).foregroundStyle(.orange) }
                    Text("Choose a range within the last 30 days of indexed local activity.")
                        .font(.caption2).foregroundStyle(StudioStyle.muted)
                }
            }
            if report.buckets.isEmpty {
                ContentUnavailableView(store.activityScanning ? "Indexing Local Sessions" : "No Recorded Sessions",
                    systemImage: "chart.bar.xaxis",
                    description: Text(store.activityScanning ? "The first scan reads your local logs. Later scans read appended data." : "No native Claude Code or Codex token records were found in this range."))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                chart
                hoverReadout
                HStack {
                    Text(selection == nil ? "Showing: \(intervalLabel(interval)) · Drag to select." : selectedLabel + " · Bars show whole bins; totals use the exact selection.")
                    Spacer()
                    Text("\(store.activityScanning ? "Updating…" : "Indexed") \(store.activityUpdatedAt?.formatted(date: .omitted, time: .shortened) ?? "—")")
                }.font(.caption2).foregroundStyle(StudioStyle.muted)
                categorySummary
                breakdown
            }
            Text("Native session logs on this Mac, grouped across accounts. Claude source labels identify local Code and Cowork records; chat usage is unavailable. Tokens are not your subscription allowance. \(newOnly ? "New Only excludes cache reads and unclassified tokens." : "Cache writes count as new input; reasoning is included in output.")")
                .font(.caption2).foregroundStyle(StudioStyle.muted)
        }
        .studioPanel()
        .onAppear { rebuild() }
        .onChange(of: store.activityRevision) { rebuild() }
        .onChange(of: days) { selection = nil; zoom = nil; editingInterval = false; resolution = days == 1 ? .hourly : .daily; rebuild() }
        .onChange(of: resolution) { rebuild() }
        .onChange(of: grouping) { rebuild() }
        .onChange(of: newOnly) { rebuild() }
        .onChange(of: selection) { rebuild() }
    }

    private var chart: some View {
        Chart {
            ForEach(report.buckets) { bucket in
                ForEach(Array(parts.enumerated()), id: \.element) { index, part in
                    let amount = value(bucket.tokens, part: part)
                    let lower = parts.prefix(index).reduce(0) { $0 + value(bucket.tokens, part: $1) }
                    if amount > 0 {
                        let bar = StudioBarLayout.inset(start: bucket.start, end: bucket.end, within: interval)
                        RectangleMark(xStart: .value("Bucket Start", bar.start),
                                      xEnd: .value("Bucket End", bar.end),
                                      yStart: .value("Token Start", lower), yEnd: .value("Token End", lower + amount))
                            .foregroundStyle(partColor(part))
                            .cornerRadius(2)
                            .opacity(selection == nil || bucket.end > report.selectedInterval.start && bucket.start < report.selectedInterval.end ? 1 : 0.2)
                    }
                }
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: 0...max(1, report.buckets.map { $0.tokens.value(newOnly: newOnly) }.max() ?? 0))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                StudioChartSelection(proxy: proxy, selection: $selection)
                    .onContinuousHover { phase in
                        guard case .active(let location) = phase, let anchor = proxy.plotFrame else {
                            hoveredDate = nil; return
                        }
                        let plot = geometry[anchor]
                        guard plot.contains(location) else { hoveredDate = nil; return }
                        hoveredDate = proxy.value(atX: location.x - plot.minX, as: Date.self)
                    }
            }
        }
        .chartXAxis {
            if interval.duration <= 2 * 3600 {
                AxisMarks(values: .stride(by: .minute, count: interval.duration <= 1800 ? 5 : 15)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            } else if interval.duration <= 2 * 86400 {
                AxisMarks(values: .stride(by: .hour, count: interval.duration <= 6 * 3600 ? 1 : 4)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: interval.duration > 14 * 86400 ? 5 : 1)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { axis in
                AxisGridLine().foregroundStyle(.white.opacity(0.05))
                AxisValueLabel { if let number = axis.as(Double.self) { Text(StudioFormat.tokens(Int(number))) } }
            }
        }
        .frame(height: 220)
    }

    private var hoverReadout: some View {
        HStack(spacing: 14) {
            if let bucket = hoveredBucket {
                Text(intervalLabel(DateInterval(start: max(interval.start, bucket.start), end: min(interval.end, bucket.end))))
                    .foregroundStyle(.white.opacity(0.8))
                ForEach(parts, id: \.self) { part in
                    HStack(spacing: 4) {
                        Circle().fill(partColor(part)).frame(width: 6, height: 6)
                        Text("\(part) \(StudioFormat.tokens(value(bucket.tokens, part: part)))")
                    }
                }
            } else {
                Text(hoveredDate == nil ? "Hover over a bar for its breakdown." : "No recorded activity in this interval.")
            }
            Spacer(minLength: 0)
        }.font(.caption2).foregroundStyle(StudioStyle.muted).frame(minHeight: 18, alignment: .leading)
    }

    private var categorySummary: some View {
        HStack(spacing: 22) {
            ForEach(parts, id: \.self) { part in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Circle().fill(partColor(part)).frame(width: 7, height: 7)
                        Text(part).font(.caption2).foregroundStyle(StudioStyle.muted)
                    }
                    Text(StudioFormat.tokens(value(report.totals, part: part))).font(.system(size: 13, weight: .medium, design: .monospaced))
                }
            }
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(grouping.rawValue.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2)
            ForEach(report.groups.prefix(8)) { group in groupRow(group) }
            if report.groups.count > 8 {
                DisclosureGroup("\(report.groups.count - 8) More") {
                    ForEach(Array(report.groups.dropFirst(8))) { group in groupRow(group) }
                }.font(.caption)
            }
        }.padding(.top, 6)
    }

    @ViewBuilder private func groupRow(_ group: ActivityGroup) -> some View {
        if group.children.isEmpty { row(group) }
        else {
            DisclosureGroup { ForEach(group.children) { row($0).padding(.leading, 10) } }
                label: { row(group) }
        }
    }
    private func row(_ group: ActivityGroup) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(group.detail.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(StudioStyle.muted).lineLimit(1).truncationMode(.middle)
            }.frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.06)).overlay(alignment: .leading) {
                    Capsule().fill(accent).frame(width: geometry.size.width * min(1,
                        Double(group.tokens.value(newOnly: newOnly)) / Double(max(1, report.totals.value(newOnly: newOnly)))))
                }
            }.frame(width: 115, height: 4)
            Text(StudioFormat.tokens(group.tokens.value(newOnly: newOnly)))
                .font(.system(size: 12, design: .monospaced)).frame(width: 75, alignment: .trailing)
        }.padding(.vertical, 3)
    }

    private var shareImage: StudioShareImage {
        let range = report.selectedInterval
        let format = Date.FormatStyle().month(.abbreviated).day().hour().minute()
        let selectedEvents = store.activityEvents.filter { $0.timestamp >= range.start && $0.timestamp < range.end }
        let selectedReport = ActivityReport.build(events: selectedEvents, provider: provider,
            interval: range, resolution: resolution, grouping: grouping, newOnly: newOnly)
        return StudioShareImage(title: "\(providerName) · Local Sessions",
            interval: "\(range.start.formatted(format)) – \(range.end.formatted(format))",
            value: "\(StudioFormat.tokens(report.totals.value(newOnly: newOnly))) \(newOnly ? "new tokens" : "tokens")",
            note: "Local session logs on this Mac, across accounts. Claude sources cover local Code and Cowork records; chat usage is unavailable. Tokens are not subscription allowance. \(newOnly ? "Excludes cache reads and unclassified tokens." : "Includes cached tokens.")",
            bars: selectedReport.buckets.map {
                StudioShareBar(date: $0.start, value: Double($0.tokens.value(newOnly: newOnly)))
            }, accent: accent)
    }
    private func intervalLabel(_ range: DateInterval) -> String {
        let format = Date.FormatStyle().month(.abbreviated).day().hour().minute()
        return "\(range.start.formatted(format)) – \(range.end.formatted(format))"
    }
    private var selectedLabel: String { "Selected: \(intervalLabel(report.selectedInterval))" }
    private func value(_ tokens: ActivityTokens, part: String) -> Int {
        switch part { case "Cached": tokens.cached; case "New Input": tokens.input; case "Output": tokens.output; default: tokens.unclassified }
    }
    private func zoomToSelection() {
        guard let selection else { return }
        let end = min(interval.end, selection.upperBound.addingTimeInterval(0.000_001))
        guard let range = StudioActivityInterval.bounded(start: selection.lowerBound, end: end, within: interval) else {
            intervalError = "Select at least one second to zoom."
            return
        }
        intervalError = nil; zoom = range; self.selection = nil; rebuild()
    }
    private func applyCustomInterval() {
        guard let range = StudioActivityInterval.bounded(start: customStart, end: customEnd, within: available) else {
            intervalError = "Choose an end time after the start time within the available range."
            return
        }
        zoom = range; selection = nil; editingInterval = false; intervalError = nil; rebuild()
    }
    private func rebuild() {
        report = ActivityReport.build(events: store.activityEvents, provider: provider,
            interval: interval, resolution: resolution, grouping: grouping, selection: selection, newOnly: newOnly)
    }
}

/// Validates a viewport without inventing a duration or silently changing the requested boundaries.
struct StudioActivityInterval {
    static func bounded(start: Date, end: Date, within bounds: DateInterval) -> DateInterval? {
        guard start >= bounds.start, end <= bounds.end, end.timeIntervalSince(start) >= 1 else { return nil }
        return DateInterval(start: start, end: end)
    }
}

/// Leave space between adjacent recorded bins without creating bars for missing bins.
struct StudioBarLayout {
    static func inset(start: Date, end: Date, within interval: DateInterval) -> DateInterval {
        let clippedStart = max(start, interval.start)
        let clippedEnd = min(end, interval.end)
        let padding = max(0, clippedEnd.timeIntervalSince(clippedStart)) * 0.14
        return DateInterval(start: clippedStart.addingTimeInterval(padding), end: clippedEnd.addingTimeInterval(-padding))
    }
}
