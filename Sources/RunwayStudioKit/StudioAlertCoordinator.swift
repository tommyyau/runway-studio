import AppKit
import Observation
import UserNotifications

private final class StudioNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in StudioWindows.openAlerts?() }
        completionHandler()
    }
}

@MainActor @Observable
final class StudioAlertCoordinator {
    var preferences = StudioAlertPreferences() { didSet { _ = persist() } }
    private(set) var feed: [StudioAlertEvent] = []
    private(set) var permission = "Not Checked"
    private(set) var deliveryError: String?
    private(set) var storageError: String?
    private(set) var testStatus: String?
    private var engine = StudioAlertEngine()
    private let file: URL
    private var canPersist = true
    private var evaluating = false
    private var requesting = false
    private var permissionRequestFailed = false
    private let suppressed: Bool
    private let center = UNUserNotificationCenter.current()
    private let delegate = StudioNotificationDelegate()

    private struct Saved: Codable {
        var preferences: StudioAlertPreferences
        var engine: StudioAlertEngine
        var feed: [StudioAlertEvent]
    }

    init(directory: URL, suppressed: Bool = false) {
        self.suppressed = suppressed
        file = directory.appendingPathComponent("alert-state.json")
        center.delegate = delegate
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: file.path) {
                let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))
                preferences = saved.preferences; engine = saved.engine; feed = saved.feed
            }
        } catch {
            canPersist = false; preferences.enabled = false
            storageError = "Saved alert state could not be read. Alerts are paused and the existing file is preserved. \(error.localizedDescription)"
        }
    }

    func refreshPermission(request: Bool = false) async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined, request {
            guard !requesting else { return }
            requesting = true
            do { _ = try await center.requestAuthorization(options: [.alert]) }
            catch {
                permissionRequestFailed = true
                deliveryError = "Notification permission could not be requested: \(error.localizedDescription)"
            }
            requesting = false
            await refreshPermission()
            return
        }
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            permission = "Allowed"
            if permissionRequestFailed { deliveryError = nil; permissionRequestFailed = false }
        case .denied: permission = "Blocked In System Settings"
        case .notDetermined: permission = "Permission Needed"
        default: permission = "Unavailable"
        }
    }

    func process(_ observations: [StudioAlertObservation], now: Date) async {
        guard !evaluating, canPersist, !suppressed else { return }
        evaluating = true
        defer { evaluating = false }
        let before = engine
        let events = engine.evaluate(observations, now: now, preferences: preferences)
        for event in events where !feed.contains(where: { $0.id == event.id }) {
            feed.insert(event, at: 0)
        }
        feed = Array(feed.prefix(100))
        guard before != engine || !events.isEmpty else { return }
        guard persist() else { return }
        await refreshPermission()
        guard !requesting else { return }
        for event in events {
            guard preferences.enabled else { break }
            if permission == "Allowed" {
                do {
                    try await send(event)
                    deliveryError = nil
                    engine.acknowledge(event, now: now)
                } catch {
                    deliveryError = "System notification delivery failed; the alert is available here and will retry for up to 30 minutes. \(error.localizedDescription)"
                }
            } else {
                // The in-app feed is an actual delivery. Do not replay old alerts when permission
                // is granted later; only new events should become new system notifications.
                engine.acknowledge(event, now: now)
            }
        }
        _ = persist()
    }

    func sendTest() async {
        await refreshPermission(request: true)
        guard permission == "Allowed" else { testStatus = "System notifications are not allowed. Enable them in macOS System Settings."; return }
        let event = StudioAlertEvent(id: "studio-test", account: "test", kind: .test,
            title: "Runway Studio Test Notification", body: "This is a test. Your allowance has not changed.", createdAt: Date())
        do {
            try await send(event)
            try? await Task.sleep(for: .milliseconds(150))
            let delivered = await center.deliveredNotifications()
            testStatus = delivered.contains { $0.request.identifier == event.id }
                ? "macOS confirmed the test in Notification Centre."
                : "Test notification submitted to macOS."
        }
        catch { testStatus = "Test delivery failed: \(error.localizedDescription)" }
    }

    private func send(_ event: StudioAlertEvent) async throws {
        let content = UNMutableNotificationContent()
        content.title = event.title; content.body = event.body
        content.threadIdentifier = "runway-studio.\(event.account)"
        try await center.add(UNNotificationRequest(identifier: event.id, content: content, trigger: nil))
    }

    private func persist() -> Bool {
        guard canPersist else { return false }
        do {
            let data = try JSONEncoder().encode(Saved(preferences: preferences, engine: engine, feed: feed))
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            storageError = nil
            return true
        } catch {
            storageError = "Alert state could not be saved. System delivery is paused. \(error.localizedDescription)"
            return false
        }
    }
}
