import Charts
import SwiftUI

struct StudioGlidePath: View {
    let snapshot: StudioSnapshot
    let store: StudioStore
    let accent: Color
    @Binding var selectedWindow: Date?
    var compact = false
    @State private var includeImported = true

    var body: some View {
        if let line = snapshot.weekly, let reset = line.resetsAt, let duration = line.duration {
            let account = store.account(for: snapshot)
            let nativeWindows = account.map { store.archive.windows(account: $0) } ?? []
            let importedWindows = includeImported ? store.importedHistory.windows(family: snapshot.family) : []
            let resets = windowDates(native: nativeWindows, imported: importedWindows, current: reset)
            let shownReset = selectedWindow.flatMap { chosen in resets.min(by: { abs($0.timeIntervalSince(chosen)) < abs($1.timeIntervalSince(chosen)) }).flatMap { abs($0.timeIntervalSince(chosen)) <= 120 ? $0 : nil } } ?? reset
            let start = shownReset.addingTimeInterval(-duration)
            let native = account.map { store.archive.current(account: $0, reset: shownReset) } ?? []
            let imported = includeImported ? store.importedHistory.current(family: snapshot.family, reset: shownReset) : []
            let points = (native + imported).sorted { $0.date < $1.date }
            let previous = resets.last { $0 < shownReset.addingTimeInterval(-2) }
            let next = resets.first { $0 > shownReset.addingTimeInterval(2) }
            let current = abs(shownReset.timeIntervalSince(reset)) < 2
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(compact ? "WEEKLY TREND" : "WEEKLY ALLOWANCE").font(.system(size: 10, weight: .semibold)).tracking(1.3)
                    Spacer()
                    Button { selectedWindow = previous } label: { Image(systemName: "chevron.left") }
                        .disabled(previous == nil).buttonStyle(.borderless).accessibilityLabel("Previous Observed Window")
                    Text(current ? "This Week" : shownReset.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundStyle(StudioStyle.muted)
                    Button { selectedWindow = next } label: { Image(systemName: "chevron.right") }
                        .disabled(next == nil).buttonStyle(.borderless).accessibilityLabel("Next Observed Window")
                    if !compact {
                    StudioImageShareControl(image: StudioShareImage(title: "\(snapshot.displayName) · Allowance",
                        interval: "\(start.formatted(date: .abbreviated, time: .shortened)) – \(shownReset.formatted(date: .abbreviated, time: .shortened))",
                        value: points.last.map { "\(Int($0.remaining.rounded()))% Left At Last Reading" } ?? "No Recorded Reading",
                        note: "Observed provider allowance. Imported source accounts remain separate from Studio accounts; gaps are unobserved.",
                        bars: points.map { StudioShareBar(date: $0.date, value: $0.remaining) }, accent: accent))
                    }
                }
                chart(native: native, imported: imported, start: start, reset: shownReset, current: current)
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 5, height: 5)
                    Text("Observed")
                    Text("- - Even Pace").padding(.leading, 8)
                    Spacer()
                    if !store.importedHistory.windows(family: snapshot.family).isEmpty {
                        Toggle("Include Imported", isOn: $includeImported).toggleStyle(.checkbox)
                    }
                }.font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
                if !imported.isEmpty {
                    Text(compact ? "Imported Archive · Account Match Unverified" : "Imported from Agent Runway · Account match not verified.")
                        .font(.caption2).foregroundStyle(StudioStyle.muted)
                } else {
                    Text(points.isEmpty ? "No readings recorded in this window." : "Recording since \(points[0].date.formatted(date: .abbreviated, time: .shortened)). Earlier periods are unobserved.")
                        .font(.caption2).foregroundStyle(StudioStyle.muted)
                }
                if let error = store.historyImportError { Text(error).font(.caption2).foregroundStyle(.orange) }
            }
        }
    }

    private func chart(native: [StudioReading], imported: [StudioReading], start: Date, reset: Date, current: Bool) -> some View {
        let latest = native.last ?? imported.last
        let stale = store.isStale(snapshot)
        return Chart {
            ForEach([start, reset], id: \.self) { date in
                LineMark(x: .value("Date", date), y: .value("Allowance Left", date == start ? 100.0 : 0),
                    series: .value("Line", "Even Pace"))
                    .foregroundStyle(.white.opacity(0.28)).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 5]))
            }
            ForEach(StudioGlidePoint.segments(imported)) { plotted in
                AreaMark(x: .value("Date", plotted.reading.date), yStart: .value("Zero", 0),
                    yEnd: .value("Allowance Left", plotted.reading.remaining), series: .value("Area", "Imported \(plotted.segment)"))
                    .foregroundStyle(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", plotted.reading.date), y: .value("Allowance Left", plotted.reading.remaining),
                    series: .value("Line", "Imported \(plotted.segment)"))
                    .foregroundStyle(accent.opacity(0.65)).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(StudioGlidePoint.segments(native)) { plotted in
                AreaMark(x: .value("Date", plotted.reading.date), yStart: .value("Zero", 0),
                    yEnd: .value("Allowance Left", plotted.reading.remaining), series: .value("Area", "Studio \(plotted.segment)"))
                    .foregroundStyle(LinearGradient(colors: [accent.opacity(0.28), accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", plotted.reading.date), y: .value("Allowance Left", plotted.reading.remaining),
                    series: .value("Line", "Studio \(plotted.segment)"))
                    .foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            if let latest {
                RuleMark(x: .value("Latest Reading", latest.date))
                    .foregroundStyle(accent.opacity(0.2)).lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Latest Reading", latest.date), y: .value("Allowance Left", latest.remaining))
                    .foregroundStyle(accent).symbolSize(65)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("\(current && !stale && !native.isEmpty ? "Now" : "Last") · \(Int(latest.remaining.rounded()))%")
                            .font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(accent)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(StudioStyle.panel.opacity(0.9), in: Capsule())
                    }
            }
        }
        .chartXScale(domain: start...reset).chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.04))
                AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%").font(.system(size: 9)).foregroundStyle(StudioStyle.muted) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: (0...7).map { start.addingTimeInterval(Double($0) * (reset.timeIntervalSince(start) / 7)) }) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.1))
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(StudioStyle.muted)
            }
        }
        .frame(height: compact ? 110 : 160)
    }

    private func windowDates(native: [StudioWindow], imported: [StudioWindow], current: Date) -> [Date] {
        var result = [current]
        for (windows, tolerance) in [(native, 2.0), (imported, 120.0)] {
            for window in windows where window.reset <= current.addingTimeInterval(tolerance) {
                if !result.contains(where: { abs($0.timeIntervalSince(window.reset)) <= tolerance }) { result.append(window.reset) }
            }
        }
        return result.sorted()
    }
}
