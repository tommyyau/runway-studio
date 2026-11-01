import AppKit
import Foundation
import Observation

@MainActor @Observable
final class StudioStore {
    let providerCache: StudioProviderCache
    let display: StudioDisplayStore
    var customizationPresented = false
    var snapshots: [StudioSnapshot] = []
    var identities: [String: String] = [:]
    var archive = StudioArchive()
    var importedHistory = StudioImportedHistory()
    var historyImportError: String?
    var connected = false
    var error: String?
    var providerErrors: [String: String] = [:]
    var now = Date()
    var loading = false
    var manualRefreshing = false
    private var lastManualMessage: String?
    var refreshMessage: String? {
        (manualRefreshing || polling.isPolling) ? polling.message
            : lastManualMessage.map { $0 + " " + pollingSummary }
    }
    var providerRefreshing: Bool { polling.isPolling }
    var pollingSummary: String { polling.scheduleSummary(now: now) }
    let polling: StudioPollingCoordinator
    var activityEvents: [ActivityEvent] = []
    var activityScanning = false
    var activityUpdatedAt: Date?
    var activityRevision = 0
    let alerts: StudioAlertCoordinator
    let serviceStatus = StudioServiceStatusStore()
    @ObservationIgnored private var monitoring: Task<Void, Never>?
    @ObservationIgnored private var manualTask: Task<Void, Never>?
    @ObservationIgnored private var providerTask: Task<Void, Never>?
    private let activityIndex = StudioActivityIndex()
    private var canSaveArchive = true
    private var cacheReadable = false
    private let archiveURL: URL

    init(directory: URL? = nil, alertsSuppressed: Bool = false,
         historyImportSource: URL? = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AgentRunway/readings.json")) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RunwayStudio", isDirectory: true)
        let cache = StudioProviderCache(directory: root)
        providerCache = cache
        display = StudioDisplayStore(directory: root)
        archiveURL = root.appendingPathComponent("allowance-history.json")
        polling = StudioPollingCoordinator(directory: root, suppressed: alertsSuppressed,
            client: StudioManualRefreshClient(runner: { arguments, timeout in try await cache.run(arguments, timeout: timeout) }),
            readCache: { Array(try cache.read().snapshots.values) })
        alerts = StudioAlertCoordinator(directory: root, suppressed: alertsSuppressed)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                archive = try JSONDecoder().decode(StudioArchive.self, from: Data(contentsOf: archiveURL))
            }
            do {
                if let historyImportSource {
                    importedHistory = try StudioImportedHistory.load(directory: root, source: historyImportSource, now: Date())
                }
            } catch {
                historyImportError = "Saved history could not be imported. Existing files are preserved. \(error.localizedDescription)"
                NSLog("Runway Studio: %@", historyImportError!)
            }
        } catch {
            canSaveArchive = false
            self.error = "Allowance history could not be read. The existing file has been preserved. \(error.localizedDescription)"
        }
    }

    /// An isolated store for the documentation renderer. Never starts monitoring or reads user history.
    static func documentationPreview(directory: URL) -> StudioStore {
        let store = StudioStore(directory: directory, alertsSuppressed: true, historyImportSource: nil)
        store.cacheReadable = true
        store.connected = true
        return store
    }

    func refresh(includeActivity: Bool = true) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        now = Date()
        polling.checkCompetitors()
        connected = polling.active
        providerErrors = Dictionary(snapshots.compactMap { snapshot in
            polling.errors[snapshot.family].map { (snapshot.id, $0) }
        }, uniquingKeysWith: { _, last in last })
        do {
            let payload = try providerCache.read()
            cacheReadable = true
            identities = payload.producedByIdentityKeys
            snapshots = payload.snapshots.values.filter { ["claude", "codex"].contains($0.family)
            }.sorted {
                if $0.family != $1.family { return $0.family == "claude" }
                return $0.displayName < $1.displayName
            }
            if snapshots.isEmpty {
                snapshots = ["claude", "codex"].map {
                    StudioSnapshot(providerID: $0, displayName: $0.capitalized,
                        refreshedAt: Date(timeIntervalSince1970: 0), lines: [])
                }
            }
            polling.reconcile(snapshots: snapshots)
            connected = polling.active
            providerErrors = Dictionary(snapshots.compactMap { snapshot in
                polling.errors[snapshot.family].map { (snapshot.id, $0) }
            }, uniquingKeysWith: { _, last in last })
            if canSaveArchive { error = polling.problem ?? polling.conflict }
            if connected, canSaveArchive {
                let previous = archive.readings
                for snapshot in snapshots where providerErrors[snapshot.providerID] == nil {
                    archive.record(snapshot, identity: identities[snapshot.providerID], now: now)
                }
                if archive.readings != previous {
                    do {
                        let data = try JSONEncoder().encode(archive)
                        try data.write(to: archiveURL, options: [.atomic])
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveURL.path)
                    } catch {
                        self.error = "Allowance history could not be saved. \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            cacheReadable = false
            self.error = "Studio’s provider cache is unavailable. The existing file has been preserved. \(error.localizedDescription)"
        }
        if includeActivity {
            Task { await refreshActivity() }
            Task { await serviceStatus.refresh() }
        }
        polling.publish(snapshots: snapshots, stale: { isStale($0) }, now: now)
        await alerts.process(alertObservations(), now: now)
    }

    func requestManualRefresh() {
        guard manualTask == nil else { return }
        manualTask = Task { [weak self] in
            await self?.manualRefresh()
            self?.manualTask = nil
        }
    }

    func manualRefresh() async {
        guard !manualRefreshing else { return }
        manualRefreshing = true
        defer { manualRefreshing = false }
        await refresh(includeActivity: false)
        guard cacheReadable else {
            lastManualMessage = "Polling is paused until the saved account cache can be read."
            return
        }
        let result = await polling.poll(snapshots: snapshots)
        await refresh(includeActivity: false)
        lastManualMessage = polling.problem ?? polling.conflict ?? (snapshots.isEmpty ? result : "Provider schedule checked.")
    }

    func startMonitoring() {
        guard monitoring == nil else { return }
        monitoring = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                if self.cacheReadable && self.providerTask == nil {
                    self.providerTask = Task { [weak self] in
                        guard let self else { return }
                        _ = await self.polling.poll(snapshots: self.snapshots)
                        await self.refresh(includeActivity: false)
                        self.providerTask = nil
                    }
                }
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }
    func stopMonitoring() { monitoring?.cancel(); monitoring = nil; manualTask?.cancel(); manualTask = nil; providerTask?.cancel(); providerTask = nil }

    func alertObservations() -> [StudioAlertObservation] {
        snapshots.compactMap { snapshot in
            guard let account = account(for: snapshot) else { return nil }
            return StudioAlertObservation(account: account, cardID: snapshot.providerID, name: snapshot.displayName,
                family: snapshot.family, fetchedAt: snapshot.refreshedAt,
                weekly: StudioAlertMeter(snapshot.weekly), session: StudioAlertMeter(snapshot.session),
                credits: (snapshot.resets?.values?.first?.number).map { Int(max(0, min(1000000, $0))) },
                expiries: snapshot.resets?.expiriesAt ?? [], fresh: !isStale(snapshot) && snapshot.warning == nil)
        }
    }
    func morningPreview() -> String {
        StudioAlertText.morning(alertObservations(), now: Date(), preferences: alerts.preferences)
    }

    func refreshActivity() async {
        guard !activityScanning else { return }
        activityScanning = true
        defer { activityScanning = false }
        activityEvents = await activityIndex.scan(now: Date())
        activityUpdatedAt = Date()
        activityRevision += 1
    }

    func account(for snapshot: StudioSnapshot) -> String? {
        identities[snapshot.providerID].map { snapshot.providerID + ":" + $0 }
    }
    func isStale(_ snapshot: StudioSnapshot) -> Bool {
        !connected || !cacheReadable || snapshot.isStale(now: now)
            || polling.hasFailure(family: snapshot.family)
            || providerErrors[snapshot.id] != nil || snapshot.loginRequired == true || snapshot.waitsForProvider
    }
    func openAccounts() {
        StudioWindows.openAccounts?()
    }
    func shareText(_ snapshot: StudioSnapshot) {
        guard let left = snapshot.weekly?.remaining else { return }
        let freshness = isStale(snapshot) ? "Cached" : "Updated"
        let reset = snapshot.weekly?.resetsAt?.formatted(date: .abbreviated, time: .shortened) ?? "unknown"
        let text = "\(snapshot.displayName): \(Int(left.rounded()))% weekly allowance left\nResets: \(reset)\n\(freshness): \(snapshot.refreshedAt.formatted())\nRunway Studio"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private enum StudioReadError: LocalizedError {
        case missingCache
        var errorDescription: String? { "No supported Runway snapshot cache was found." }
    }
}
