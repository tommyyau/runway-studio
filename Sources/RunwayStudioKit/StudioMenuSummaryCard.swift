import Charts
import SwiftUI

struct StudioMenuSummaryCard: View {
    let snapshots: [StudioSnapshot]
    let now: Date
    @State private var range = StudioSummaryRange.month
    @State private var showCost = true

    private var values: [StudioSummaryValue] { StudioSummaryValue.build(snapshots: snapshots, range: range, now: now) }
    private var total: Double? {
        let recorded = values.compactMap { $0.value(cost: showCost) }
        return recorded.isEmpty ? nil : recorded.reduce(0, +)
    }
    private var partial: Bool { showCost && values.contains { $0.incomplete || $0.cost == nil } }
    private func readout(_ value: Double?) -> String {
        guard let value else { return "No Record" }
        return showCost ? StudioFormat.money(value) : StudioFormat.tokens(Int(value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Menu {
                    Button("Estimated API Value") { showCost = true }
                    Button("Tokens") { showCost = false }
                } label: {
                    HStack(spacing: 5) {
                        Text(showCost ? "API Value" : "Tokens").font(.system(size: 15, weight: .semibold))
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                }.menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Summary Measure")
                Spacer()
                if partial { Text("Partial Estimate").font(.caption2).foregroundStyle(.orange) }
            }.padding(.horizontal, 4)
            VStack(spacing: 14) {
                Picker("Summary Range", selection: $range) {
                    ForEach(StudioSummaryRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.06), lineWidth: 21).padding(12)
                        Chart(values) { item in
                            if let value = item.value(cost: showCost), value > 0 {
                                SectorMark(angle: .value("Value", value), innerRadius: .ratio(0.7), angularInset: 2)
                                    .cornerRadius(3)
                                    .foregroundStyle(item.id == "claude" ? StudioStyle.mint : StudioStyle.violet)
                            }
                        }.chartLegend(.hidden)
                        VStack(spacing: 3) {
                            Text(total.map { showCost ? ($0 < 1000 ? StudioFormat.money($0) : "$" + StudioFormat.tokens(Int($0))) : StudioFormat.tokens(Int($0)) } ?? "—")
                                .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(showCost ? "API Estimate" : "Tokens").font(.system(size: 9)).foregroundStyle(StudioStyle.muted)
                        }.accessibilityElement(children: .ignore)
                            .accessibilityLabel("Total \(readout(total))")
                    }.frame(width: 142, height: 142)
                    VStack(spacing: 13) {
                        ForEach(values) { item in
                            HStack(spacing: 7) {
                                Circle().fill(item.id == "claude" ? StudioStyle.mint : StudioStyle.violet).frame(width: 7, height: 7)
                                Text(item.name)
                                Spacer(minLength: 0)
                                Text(readout(item.value(cost: showCost))).monospacedDigit().foregroundStyle(StudioStyle.muted)
                            }.font(.caption)
                        }
                    }.frame(maxWidth: .infinity)
                }
                Text(showCost ? "Estimated API Value · Not Your Subscription Bill" : "Recorded Tracker History · Includes Cached Tokens")
                    .font(.system(size: 10)).foregroundStyle(StudioStyle.muted)
            }.padding(16).background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
