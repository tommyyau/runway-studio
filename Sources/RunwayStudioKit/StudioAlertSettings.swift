import AppKit
import ServiceManagement
import SwiftUI

struct StudioAlertSettings: View {
    let store: StudioStore
    @Bindable var alerts: StudioAlertCoordinator
    @State private var preview: String?
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Alerts & Morning Report").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("Useful changes, with a saved history and controls for every alert.")
                        .font(.callout).foregroundStyle(StudioStyle.muted)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Enable Alerts", isOn: $alerts.preferences.enabled)
                        .onChange(of: alerts.preferences.enabled) { if alerts.preferences.enabled { Task { await alerts.refreshPermission(request: true) } } }
                    HStack {
                        Text("macOS Notifications: \(alerts.permission)").font(.caption)
                        Spacer()
                        if alerts.permission == "Blocked In System Settings" {
                            Button("Open System Settings") {
                                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        } else {
                            Button(alerts.permission == "Allowed" ? "Refresh Permission" : "Request Permission") {
                                Task { await alerts.refreshPermission(request: true) }
                            }
                        }
                    }
                    Button("Send Test Notification") { Task { await alerts.sendTest() } }
                    if let status = alerts.testStatus { Text(status).font(.caption).foregroundStyle(StudioStyle.muted) }
                    if let error = alerts.deliveryError ?? alerts.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
                    Text("Without macOS permission, new alerts still appear in the history below. System banners may be suppressed by Focus or your macOS notification style.")
                        .font(.caption).foregroundStyle(StudioStyle.muted)
                }.studioPanel()
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Daily Morning Report", isOn: $alerts.preferences.morning)
                    DatePicker("Report Time", selection: reportTime, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, TimeZone(identifier: alerts.preferences.timeZoneID) ?? .current)
                    Text("Europe/London · GMT/BST follows daylight saving. A missed report can arrive on wake within four hours; old reports are skipped.")
                        .font(.caption).foregroundStyle(StudioStyle.muted)
                    Button("Preview Morning Report") { preview = store.morningPreview() }
                    if let preview { Text(preview).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }.studioPanel()
                VStack(alignment: .leading, spacing: 13) {
                    Text("Allowance Alerts").font(.headline)
                    Toggle("Low Allowance (10% Or Less)", isOn: $alerts.preferences.lowAllowance)
                    Toggle("May Run Out At Least 12 Hours Early", isOn: $alerts.preferences.forecast)
                    Toggle("Allowance Or Readings Restored", isOn: $alerts.preferences.recovery)
                    Toggle("Early Weekly Reset Or New Credits", isOn: $alerts.preferences.resetChanges)
                    Toggle("Reset Credit Expiry (24h And 2h)", isOn: $alerts.preferences.expiry)
                    Toggle("Plenty To Spare Before Renewal", isOn: $alerts.preferences.spare)
                    Text("Forecast and spare warnings occur at most once per weekly window. Spare notices only appear from 08:00–20:00 London time. The first reading establishes a baseline; stale data never triggers allowance alerts.")
                        .font(.caption).foregroundStyle(StudioStyle.muted)
                    dropRule("Claude", rule: $alerts.preferences.claudeDrop)
                    dropRule("Codex", rule: $alerts.preferences.codexDrop)
                }.studioPanel()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Background Monitoring").font(.headline)
                    Text("Closing the dashboard keeps Studio running when alerts are enabled. Quit Studio stops monitoring. Studio checks account readings itself; keep Agent Runway and the original Runway GUI closed.")
                        .font(.caption).foregroundStyle(StudioStyle.muted)
                    Toggle("Open Studio At Login", isOn: $loginEnabled)
                        .onChange(of: loginEnabled) { updateLoginItem() }
                    if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.orange) }
                }.studioPanel()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Recent Alerts").font(.headline)
                    if alerts.feed.isEmpty { Text("No alerts yet. Test notifications do not change allowance history.").foregroundStyle(StudioStyle.muted).font(.caption) }
                    ForEach(alerts.feed.prefix(20)) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.title).font(.system(size: 13, weight: .semibold))
                            Text(event.body).font(.caption).foregroundStyle(StudioStyle.muted).fixedSize(horizontal: false, vertical: true)
                            Text(event.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(StudioStyle.muted)
                        }
                        Divider()
                    }
                }.studioPanel()
            }.padding(24)
        }
        .background(StudioStyle.background).foregroundStyle(.white).preferredColorScheme(.dark)
        .frame(minWidth: 560, minHeight: 600)
        .task { await alerts.refreshPermission() }
    }

    private var reportTime: Binding<Date> {
        let calendar = StudioAlertEngine.calendar(alerts.preferences)
        return Binding(get: {
            calendar.date(bySettingHour: alerts.preferences.hour, minute: alerts.preferences.minute, second: 0, of: Date()) ?? Date()
        }, set: { date in
            alerts.preferences.hour = calendar.component(.hour, from: date)
            alerts.preferences.minute = calendar.component(.minute, from: date)
        })
    }

    private func dropRule(_ name: String, rule: Binding<StudioDropRule>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("\(name) Rapid Allowance Drop", isOn: rule.enabled)
            if rule.wrappedValue.enabled {
                Stepper("\(rule.wrappedValue.points) Percentage Points", value: rule.points, in: 1...100)
                Stepper("Within \(rule.wrappedValue.minutes) Minutes", value: rule.minutes, in: 5...120, step: 5)
                Text("One alert per continuous drop. Rearms after a full configured window with no further decrease.")
                    .font(.caption).foregroundStyle(StudioStyle.muted)
            }
        }.padding(.top, 4)
    }

    private func updateLoginItem() {
        do {
            if loginEnabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Approve Studio in System Settings → General → Login Items." : nil
        } catch { loginMessage = "Login item could not be updated: \(error.localizedDescription)" }
    }
}
