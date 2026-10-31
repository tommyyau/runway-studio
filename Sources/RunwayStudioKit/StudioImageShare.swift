import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// A self-contained image, so the exported interval and the meaning of its numbers travel together.
struct StudioShareImage: View {
    let title: String
    let interval: String
    let value: String
    let note: String
    let bars: [StudioShareBar]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("RUNWAY STUDIO").font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
            Text(title).font(.system(size: 23, weight: .semibold, design: .rounded))
            Text(interval).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
            if !bars.isEmpty {
                Chart(bars) { bar in
                    BarMark(x: .value("Time", bar.date), y: .value("Value", bar.value))
                        .foregroundStyle(LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                        .cornerRadius(3)
                }.chartYScale(domain: 0...max(1, bars.map(\.value).max() ?? 0))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel {
                            if let number = value.as(Double.self) { Text(StudioFormat.tokens(Int(number))) }
                        }
                    }
                }.frame(height: 170)
            }
            Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(28).frame(width: 720, alignment: .leading)
        .foregroundStyle(.white)
        .background(Color(red: 0.07, green: 0.08, blue: 0.11))
        .environment(\.colorScheme, .dark)
    }
}

struct StudioShareBar: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct StudioImageShareControl: View {
    let image: StudioShareImage
    @State private var error: String?

    var body: some View {
        Menu {
            Button("Copy PNG") { copy() }
            Button("Save PNG…") { save() }
        } label: { Image(systemName: "square.and.arrow.up") }
        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Share Image")
        .alert("Could Not Share Image", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @MainActor private func png() -> Data? {
        let renderer = ImageRenderer(content: image)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage, let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
            error = "The image could not be rendered."
            return nil
        }
        return data
    }
    @MainActor private func copy() {
        guard let data = png() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.setData(data, forType: .png) { error = "The image could not be copied to the clipboard." }
    }
    @MainActor private func save() {
        guard let data = png() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Runway Studio.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { self.error = "The image could not be saved: \(error.localizedDescription)" }
    }
}
