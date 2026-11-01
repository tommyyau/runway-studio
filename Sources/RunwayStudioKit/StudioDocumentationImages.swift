import AppKit
import SwiftUI

/// Reproducible native-view illustrations, using only synthetic account/history/activity data.
public enum StudioDocumentationImages {
    @MainActor public static func export(to directory: URL) async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("studio-docs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let store = StudioStore.documentationPreview(directory: scratch)
        seed(store)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await render(StudioDashboard(store: store, exporting: true).frame(width: 1180)
            .fixedSize(horizontal: false, vertical: true).frame(height: 810, alignment: .top).clipped(),
            to: directory.appendingPathComponent("dashboard.png"))
        try await render(StudioMenuPopover(store: store, dashboard: {}, alerts: {}, quit: {}).frame(width: 440, height: 1110),
            to: directory.appendingPathComponent("menu-panel.png"))
        try await render(VStack(alignment: .leading, spacing: 14) {
            HStack { Text("RUNWAY STUDIO").font(.caption.weight(.bold)).tracking(2); Spacer(); Text("Illustrative Data").font(.caption).foregroundStyle(StudioStyle.muted) }
            StudioEventActivityCard(provider: "claude", store: store, days: 1)
        }.padding(24).frame(width: 1180).background(StudioStyle.background),
            to: directory.appendingPathComponent("activity.png"))
    }

    @MainActor private static func render<V: View>(_ content: V, to url: URL) async throws {
        // AppKit-backed controls and scroll views need a native host, not ImageRenderer.
        let view = NSHostingView(rootView: content.environment(\.colorScheme, .dark))
        let size = view.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.setFrameSize(size)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        let settledSize = view.fittingSize
        window.setContentSize(settledSize)
        view.setFrameSize(settledSize)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url, options: .atomic)
        window.close()
        print(url.lastPathComponent)
    }

    @MainActor private static func seed(_ store: StudioStore) {
        let date = ISO8601DateFormatter().date(from: "2026-11-01T10:30:00Z")!
        store.now = date
        store.display.preferences.showSummary = false
        store.display.preferences.showMenuActivity = false
        store.display.preferences.showServiceStatus = false
        store.display.preferences.showRefreshHealth = false
        store.activityUpdatedAt = date
        store.activityRevision = 1
        let resets = ["claude": ISO8601DateFormatter().date(from: "2026-11-02T08:00:00Z")!,
                      "codex": ISO8601DateFormatter().date(from: "2026-11-05T04:07:00Z")!]
        for (family, left) in [("claude", 27.0), ("codex", 64.0)] {
            let reset = resets[family]!
            var lines = [StudioLine(type: "progress", label: "Weekly", used: 100 - left, limit: 100,
                resetsAt: reset, periodDurationMs: 604_800_000)]
            if family == "claude" {
                lines.insert(StudioLine(type: "progress", label: "Session", used: 8, limit: 100,
                    resetsAt: date.addingTimeInterval(12000), periodDurationMs: 18_000_000), at: 0)
                lines.append(StudioLine(type: "progress", label: "Fable", used: 6, limit: 100,
                    resetsAt: reset, periodDurationMs: 604_800_000))
            }
            store.snapshots.append(StudioSnapshot(providerID: family, displayName: family == "claude" ? "Claude" : "Codex",
                plan: family == "claude" ? "Team 5x" : "Pro 100", refreshedAt: date, lines: lines))
            store.identities[family] = "documentation-example"
            let start = reset.addingTimeInterval(-604800)
            let span = date.timeIntervalSince(start)
            for step in 0...Int(span / 900) {
                let t = start.addingTimeInterval(Double(step) * 900)
                let progress = t.timeIntervalSince(start) / span
                let remaining = 100 - (100 - left) * pow(progress, 0.78)
                store.archive.readings.append(StudioReading(account: "\(family):documentation-example", date: t,
                    reset: reset, duration: 604800, remaining: remaining))
            }
            store.archive.readings.append(StudioReading(account: "\(family):documentation-example", date: date,
                reset: reset, duration: 604800, remaining: left))
        }
        for hour in 0..<24 {
            for (index, project) in ["Studio", "Research", "Prototype"].enumerated() {
                let weight = [3, 1, 2][index]
                let burst = [1, 1, 0, 0, 0, 0, 2, 3, 5, 8, 6, 4, 5, 7, 9, 6, 4, 3, 2, 1, 3, 4, 2, 1][hour]
                guard burst > 0 else { continue }
                store.activityEvents.append(ActivityEvent(provider: "claude", timestamp: date.addingTimeInterval(Double(hour - 24) * 3600 + 1200),
                    project: project, projectPath: "/Example Projects/\(project)", session: "example-\(index)",
                    agentID: "example-\(index)", agentRole: index == 1 ? "subagent" : "main", agentName: "Example Agent",
                    model: "Example Claude Model", tokens: ActivityTokens(input: burst * weight * 15000,
                        cached: burst * weight * 45000, output: burst * weight * 8000), source: "Claude Code"))
            }
        }
        store.archive.readings.sort { $0.date < $1.date }
    }
}
