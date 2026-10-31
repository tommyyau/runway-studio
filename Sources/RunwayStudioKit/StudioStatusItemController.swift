import AppKit
import Observation
import Runway
import SwiftUI

@MainActor final class StudioStatusItemController: NSObject, NSPopoverDelegate {
    private let store: StudioStore
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var appearanceObserver: NSKeyValueObservation?

    init(store: StudioStore, dashboard: @escaping () -> Void, alerts: @escaping () -> Void, quit: @escaping () -> Void) {
        self.store = store
        super.init()
        item.autosaveName = "RunwayStudioUsage"
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.setAccessibilityLabel("Runway Studio Usage Snapshot")
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        popover.contentSize = NSSize(width: 440, height: 680)
        popover.contentViewController = NSHostingController(rootView: StudioMenuPopover(
            store: store,
            dashboard: { [weak self] in self?.popover.performClose(nil); dashboard() },
            alerts: { [weak self] in self?.popover.performClose(nil); alerts() }, quit: quit))
        appearanceObserver = item.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.update() }
        }
        observeReadings()
    }

    func show() {
        guard let button = item.button else { return }
        if let screen = button.window?.screen {
            popover.contentSize.height = min(680, max(350, screen.visibleFrame.height - 50))
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) } else { show() }
    }

    private func entries() -> [StudioMenuEntry] {
        StudioMenuEntry.make(snapshots: store.snapshots,
            staleIDs: Set(store.snapshots.filter { store.isStale($0) }.map(\.id)), now: store.now, preferredAccounts: store.display.preferences.menuAccounts)
    }
    private func observeReadings() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeReadings() }
        }
    }
    private func update() {
        let entries = entries()
        let style = store.display.preferences.menuDisplay
        let entryWidth = CGFloat(style.width)
        let width: CGFloat = entries.isEmpty ? 28 : CGFloat(entries.count) * entryWidth + CGFloat(entries.count - 1) * 8
        let image = NSImage(size: NSSize(width: width, height: 22))
        item.button?.effectiveAppearance.performAsCurrentDrawingAppearance {
            image.lockFocus()
            if entries.isEmpty {
                NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil)?
                    .draw(in: NSRect(x: 3, y: 3, width: 20, height: 16))
            }
            for (index, entry) in entries.enumerated() { draw(entry, x: CGFloat(index) * (entryWidth + 8), style: style) }
            image.unlockFocus()
        }
        image.isTemplate = false
        item.length = width + 8
        item.button?.title = ""
        item.button?.image = image
        let summary = entries.map(\.summary).joined(separator: "; ")
        item.button?.toolTip = (summary.isEmpty ? "Runway Studio — waiting for readings" : summary)
            + "\nCells show weekly allowance (session if weekly unavailable). Stacked values: session above weekly."
        item.button?.setAccessibilityValue(summary)
    }
    private func draw(_ entry: StudioMenuEntry, x: CGFloat, style: StudioMenuDisplay) {
        let label = NSColor.labelColor
        if let path = RunwayProviderArtwork.path(for: entry.family, in: CGRect(x: x, y: 3, width: 16, height: 16)),
           let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(label.cgColor); context.addPath(path); context.fillPath()
        }
        let tint: NSColor
        switch entry.level {
        case .unavailable: tint = .secondaryLabelColor
        case .green: tint = .systemGreen
        case .orange: tint = .systemOrange
        case .red: tint = .systemRed
        }
        if style.showsBars {
        for cell in 0..<5 {
            let empty = entry.level == .red ? tint.withAlphaComponent(0.3) : label.withAlphaComponent(0.16)
            (cell < entry.cells ? tint : empty).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + 20 + CGFloat(cell) * 4, y: 5, width: 3, height: 12), xRadius: 1, yRadius: 1).fill()
        }
        }
        if entry.stale {
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(x: x + 13, y: 17, width: 4, height: 4)).fill()
        }
        func number(_ remaining: Double?, y: CGFloat, small: Bool) {
            let text = remaining.map { "\(Int($0.rounded()))%" } ?? "—"
            (text as NSString).draw(at: NSPoint(x: x + (style.showsBars ? 43 : 20), y: y), withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: small ? 9 : 11, weight: .semibold), .foregroundColor: label
            ])
        }
        guard style.showsPercentages else { return }
        if entry.session != nil, entry.weekly != nil {
            number(entry.session, y: 11, small: true); number(entry.weekly, y: 0, small: true)
        } else { number(entry.primary, y: 4, small: false) }
    }
}
