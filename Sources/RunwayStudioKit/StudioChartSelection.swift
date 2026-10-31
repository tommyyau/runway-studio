import Charts
import SwiftUI

/// Keep the selected interval after the mouse is released. The built-in chart selection gesture
/// represents the active interaction, which can clear its binding when the drag ends on macOS.
struct StudioChartSelection: View {
    let proxy: ChartProxy
    @Binding var selection: ClosedRange<Date>?

    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { update($0, geometry: geometry) }
                    .onEnded { update($0, geometry: geometry) })
        }
    }

    private func update(_ gesture: DragGesture.Value, geometry: GeometryProxy) {
        guard let anchor = proxy.plotFrame else { return }
        let plot = geometry[anchor]
        guard plot.contains(gesture.startLocation) else { return }
        let start = min(max(0, gesture.startLocation.x - plot.minX), plot.width)
        let end = min(max(0, gesture.location.x - plot.minX), plot.width)
        guard let a = proxy.value(atX: start, as: Date.self),
              let b = proxy.value(atX: end, as: Date.self) else { return }
        selection = min(a, b)...max(a, b)
    }
}
