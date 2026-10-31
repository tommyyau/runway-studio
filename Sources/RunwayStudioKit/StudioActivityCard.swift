import Charts
import SwiftUI

struct StudioActivityCard: View {
    let snapshot: StudioSnapshot
    let days: Int
    let showCost: Bool
    let now: Date
    @State private var selectedRange: ClosedRange<Date>?

    private var points: [StudioDay] { snapshot.usageHistory?.days(count: days, now: now) ?? [] }
    private var selectedPoints: [StudioDay] {
        guard let selectedRange else { return points }
        let start = Calendar.current.startOfDay(for: selectedRange.lowerBound)
        let end = Calendar.current.startOfDay(for: selectedRange.upperBound)
        return points.filter { $0.instant >= start && $0.instant <= end }
    }
    private var models: [StudioModel] { snapshot.usageHistory?.models(in: Set(selectedPoints.map(\.date))) ?? [] }
    private var accent: Color { StudioStyle.accent(snapshot) }
    private var totalTokens: Int? { StudioDay.totalRecordedTokens(selectedPoints) }
    private var cost: Double? {
        let costs = selectedPoints.compactMap(\.costUSD)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }
    private var unpriced: Bool {
        let keys = Set(selectedPoints.map(\.date))
        return (snapshot.usageHistory?.unknownModelsByDay ?? [:]).contains { keys.contains($0.key) && !$0.value.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.family == "claude" ? "Claude" : "Codex").font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                StudioImageShareControl(image: shareImage)
                if selectedRange != nil {
                    Button("Clear Selection") { selectedRange = nil }.font(.caption).buttonStyle(.borderless)
                }
                    Text(showCost ? (cost.map(StudioFormat.money) ?? "No Estimate") : (totalTokens.map(StudioFormat.tokens) ?? "No Record"))
                        .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(showCost ? "estimated API value" : "tokens")
                        .font(.caption).foregroundStyle(StudioStyle.muted)
            }
            if points.contains(where: { $0.totalTokens != nil }) {
                Chart(points) { point in
                    if let value = chartValue(point) {
                        BarMark(x: .value("Day", point.instant, unit: .day), y: .value(showCost ? "USD" : "Tokens", value))
                            .foregroundStyle(LinearGradient(colors: [accent, accent.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                            .cornerRadius(3)
                            .opacity(selectedRange == nil || selectedPoints.contains(where: { $0.id == point.id }) ? 1 : 0.2)
                    }
                }
                .chartYScale(domain: 0...max(1, points.compactMap(chartValue).max() ?? 0))
                .chartOverlay { proxy in StudioChartSelection(proxy: proxy, selection: $selectedRange) }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: days > 14 ? 5 : 1)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.05))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(showCost ? StudioFormat.money(number) : StudioFormat.tokens(Int(number)))
                            }
                        }
                    }
                }
                .frame(height: 160)
                .onChange(of: days) { selectedRange = nil }
                Text(selectedRange == nil ? "Drag across the bars to select days." : "Selected: \(selectedPoints.first?.date ?? "—") to \(selectedPoints.last?.date ?? "—")")
                    .font(.caption2).foregroundStyle(StudioStyle.muted)
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("MODEL BREAKDOWN").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                        Text("Same date range as the chart").font(.caption2).foregroundStyle(StudioStyle.muted)
                    }.frame(width: 155, alignment: .leading)
                    VStack(spacing: 10) {
                        ForEach(models.prefix(8)) { model in
                            modelRow(model)
                        }
                        if models.count > 8 {
                            DisclosureGroup("\(models.count - 8) More Models") {
                                ForEach(Array(models.dropFirst(8))) { model in modelRow(model) }
                            }.font(.caption)
                        }
                    }.frame(maxWidth: .infinity)
                }
                .padding(.top, 5)
            } else {
                ContentUnavailableView("No Recorded Activity", systemImage: "chart.bar.xaxis",
                    description: Text("No local session-log records were found in this range."))
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
            if showCost {
                Text("Machine-local history across accounts. API-rate estimate, not your subscription bill or allowance. \(unpriced ? "Some models are unpriced; the estimate is incomplete." : "Missing prices are excluded.")")
                    .font(.caption2).foregroundStyle(unpriced ? .orange : StudioStyle.muted)
            } else {
                Text("Includes cached tokens. Blank days have no log record; they do not prove zero usage.")
                    .font(.caption2).foregroundStyle(StudioStyle.muted)
            }
        }.studioPanel()
    }

    private var shareImage: StudioShareImage {
        let start = selectedRange.map { $0.lowerBound.formatted(date: .abbreviated, time: .omitted) } ?? selectedPoints.first?.date ?? "No recorded day"
        let end = selectedRange.map { $0.upperBound.formatted(date: .abbreviated, time: .omitted) } ?? selectedPoints.last?.date ?? "No recorded day"
        return StudioShareImage(title: "\(snapshot.family == "claude" ? "Claude" : "Codex") · Local Activity", interval: "\(start) – \(end)",
            value: showCost ? (cost.map(StudioFormat.money) ?? "No Estimate") : (totalTokens.map { StudioFormat.tokens($0) + " tokens" } ?? "No Record"),
            note: showCost ? "Machine-local history across accounts. Estimated API value from local logs, not a subscription bill or allowance. Missing prices are excluded.\(unpriced ? " Some models are unpriced." : "")" : "Machine-local history across accounts. Session-log tokens include cached tokens. Missing days do not prove zero usage. Tokens are not subscription allowance.",
            bars: selectedPoints.compactMap { point in chartValue(point).map { StudioShareBar(date: point.instant, value: $0) } }, accent: accent)
    }
    private func modelRow(_ model: StudioModel) -> some View {
        HStack(spacing: 12) {
            Text(model.model).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { p in
                Capsule().fill(.white.opacity(0.05)).overlay(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.7))
                        .frame(width: p.size.width * min(1, Double(model.totalTokens) / Double(max(1, totalTokens ?? 0))))
                }
            }.frame(width: 95, height: 4)
            Text(showCost ? (model.costUSD.map(StudioFormat.money) ?? "Unpriced") : StudioFormat.tokens(model.totalTokens))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(StudioStyle.muted)
                .frame(width: 75, alignment: .trailing)
        }
    }
    private func chartValue(_ point: StudioDay) -> Double? {
        showCost ? point.costUSD : point.totalTokens.map(Double.init)
    }
    private func readout(_ point: StudioDay) -> String {
        if showCost { return point.costUSD.map(StudioFormat.money) ?? "No Estimate" }
        return point.totalTokens.map { StudioFormat.tokens($0) + " tokens" } ?? "No Record"
    }
}
