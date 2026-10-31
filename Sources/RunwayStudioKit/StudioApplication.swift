import AppKit
import SwiftUI

public enum RunwayStudioApplication {
    @MainActor public static func run() {
        let application = NSApplication.shared
        let delegate = StudioAppDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor private final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var monitors: [String: NSPanel] = [:]
    private var accountsWindow: NSWindow?
    private var alertWindow: NSWindow?
    private var menuController: StudioStatusItemController?
    private let processLock = StudioProcessLock()
    private let store = StudioStore(alertsSuppressed: CommandLine.arguments.contains("--snapshot"))

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !CommandLine.arguments.contains("--snapshot") {
            do {
                guard try processLock.acquire() else {
                    NSRunningApplication.runningApplications(withBundleIdentifier: "local.runway.studio")
                        .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                        .activate(options: [.activateAllWindows])
                    NSApp.terminate(nil)
                    return
                }
            } catch {
                store.alerts.preferences.enabled = false
                store.error = "Background alerts are paused because Studio could not acquire its single-instance lock. \(error.localizedDescription)"
            }
        }
        StudioWindows.openMonitor = { [weak self] id in self?.showMonitor(id) }
        StudioWindows.openAccounts = { [weak self] in self?.showAccounts() }
        StudioWindows.openAlerts = { [weak self] in self?.showAlerts() }
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let applicationMenu = NSMenu(); item.submenu = applicationMenu
        applicationMenu.addItem(withTitle: "About Runway Studio", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Alerts & Morning Report…", action: #selector(openAlertSettings), keyEquivalent: ",").target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Runway Studio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowItem = NSMenuItem(); menu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window"); windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
        let arguments = CommandLine.arguments
        store.startMonitoring()
        if !arguments.contains("--snapshot") {
            menuController = StudioStatusItemController(store: store,
                dashboard: { [weak self] in self?.openDashboard() },
                alerts: { [weak self] in self?.showAlerts() },
                quit: { NSApp.terminate(nil) })
            if arguments.contains("--show-menu") {
                Task { @MainActor in
                    await Task.yield()
                    menuController?.show()
                }
            }
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wakeRefresh), name: NSWorkspace.didWakeNotification, object: nil)
            if store.alerts.preferences.enabled { Task { await store.alerts.refreshPermission(request: true) } }
        }
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            makeDashboard()
            guard let window else { return }
            let path = arguments[index + 1]
            Task {
                await store.refresh()
                while store.loading { try? await Task.sleep(for: .milliseconds(50)) }
                await store.refreshActivity()
                while store.activityScanning { try? await Task.sleep(for: .milliseconds(50)) }
                let view = NSHostingView(rootView: StudioDashboard(store: store, exporting: true)
                    .frame(width: 1180).fixedSize(horizontal: false, vertical: true))
                window.contentView = view
                view.setFrameSize(NSSize(width: 1180, height: view.fittingSize.height))
                view.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(200))
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    fputs("Dashboard export failed\n", stderr)
                    NSApp.terminate(nil)
                    return
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    fputs("Dashboard export failed\n", stderr)
                    NSApp.terminate(nil)
                    return
                }
                do { try png.write(to: URL(fileURLWithPath: path), options: .atomic) }
                catch { fputs("Dashboard export failed: \(error.localizedDescription)\n", stderr) }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuController?.show()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        store.stopMonitoring()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func wakeRefresh() { Task { await store.refresh() } }
    @objc private func openAlertSettings() { showAlerts() }
    @objc private func openDashboard() {
        NSApp.setActivationPolicy(.regular)
        makeDashboard()
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quitStudio() { NSApp.terminate(nil) }

    private func makeDashboard() {
        guard window == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 900),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Runway Studio"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(StudioStyle.background)
        window.minSize = NSSize(width: 900, height: 680)
        window.setFrameAutosaveName("RunwayStudioDashboard")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: StudioDashboard(store: store))
        window.center()
        self.window = window
    }

    private func showAccounts() {
        NSApp.setActivationPolicy(.regular)
        if accountsWindow == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 620),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Studio Accounts"
            panel.isReleasedWhenClosed = false
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.contentView = NSHostingView(rootView: StudioAccounts(store: store))
            panel.center()
            accountsWindow = panel
        }
        accountsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAlerts() {
        NSApp.setActivationPolicy(.regular)
        if alertWindow == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 780),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            panel.title = "Alerts & Morning Report"
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 580, height: 650)
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.contentView = NSHostingView(rootView: StudioAlertSettings(store: store, alerts: store.alerts))
            panel.setFrameAutosaveName("StudioAlerts")
            panel.center()
            alertWindow = panel
        }
        alertWindow?.deminiaturize(nil)
        alertWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMonitor(_ providerID: String) {
        NSApp.setActivationPolicy(.regular)
        if let panel = monitors[providerID] {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 740),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = (store.snapshots.first { $0.id == providerID }?.displayName ?? providerID) + " Monitor"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.minSize = NSSize(width: 430, height: 450)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.setFrameAutosaveName("StudioMonitor.\(providerID)")
        panel.contentView = NSHostingView(rootView: StudioMonitor(providerID: providerID, store: store) { [weak panel] floating in
            panel?.level = floating ? .floating : .normal
        })
        panel.center()
        monitors[providerID] = panel
        panel.makeKeyAndOrderFront(nil)
    }
}
