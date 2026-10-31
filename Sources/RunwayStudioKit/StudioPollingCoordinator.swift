import AppKit
import Foundation
import Observation
import OSLog

/// One process, one serialized provider engine, one persisted schedule for manual and automatic reads.
@MainActor @Observable final class StudioPollingCoordinator {
    private(set) var state = StudioPollState()
    private(set) var isPolling = false
    private(set) var problem: String?
    private(set) var conflict: String?
    private(set) var message = "Checking Provider Schedule…"
    private(set) var errors: [String: String] = [:]
    var active: Bool { !suppressed && problem == nil && conflict == nil }
    private let root: URL
    private let scheduleURL: URL
    private let lock: StudioProcessLock
    private let client: StudioManualRefreshClient
    private let suppressed: Bool
    private let clock: @MainActor () -> Date
    private let competitors: @MainActor () -> [String]
    private let readCache: @MainActor () throws -> [StudioSnapshot]
    private let logger = Logger(subsystem: "local.runway.studio", category: "polling")

    init(directory: URL, suppressed: Bool = false, client: StudioManualRefreshClient = .init(),
         clock: @escaping @MainActor () -> Date = Date.init,
         competitors: @escaping @MainActor () -> [String] = StudioPollingCoordinator.runningCompetitors,
         readCache: @escaping @MainActor () throws -> [StudioSnapshot] = StudioPollingCoordinator.savedSnapshots) {
        root = directory
        scheduleURL = directory.appendingPathComponent("polling-state.json")
        lock = StudioProcessLock(directory: directory, filename: "polling.lock")
        self.suppressed = suppressed
        self.client = client
        self.clock = clock
        self.competitors = competitors
        self.readCache = readCache
        guard !suppressed else { return }
        do {
            guard try lock.acquire() else { problem = "Another Studio poller is already running."; return }
            if FileManager.default.fileExists(atPath: scheduleURL.path) {
                state = try JSONDecoder().decode(StudioPollState.self, from: Data(contentsOf: scheduleURL))
            }
        } catch { fail("Polling is paused because its saved schedule could not be read. \(error.localizedDescription)") }
    }

    static func runningCompetitors() -> [String] {
        [("net.maherfamily.AgentRunway", "Agent Runway"), ("com.mattstallone.runway", "Runway")]
            .compactMap { id, title in NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty ? nil : title }
    }

    static func savedSnapshots() throws -> [StudioSnapshot] {
        Array(try StudioProviderCache.shared.read().snapshots.values)
    }

    func nextAttempt(family: String) -> Date? { state.nextAllowed(family: family) }
    func hasFailure(family: String) -> Bool { (state.records[family]?.consecutiveFailures ?? 0) > 0 }

    /// Reconcile a late provider-cache publication locally, without
    /// another request and without inventing a new provider timestamp or extending its freshness.
    func reconcile(snapshots: [StudioSnapshot]) {
        guard active, !isPolling else { return }
        var changed = false
        for family in Array(state.records.keys) {
            guard hasFailure(family: family), let attempt = state.records[family]?.lastAttempt else { continue }
            let cards = snapshots.filter { $0.family == family }
            guard !cards.isEmpty, cards.allSatisfy({ card in
                card.refreshedAt >= attempt.addingTimeInterval(-1) && card.refreshedAt <= clock().addingTimeInterval(60)
                    && !card.waitsForProvider && card.warning == nil && card.loginRequired != true
                    && card.lines.contains { $0.type == "progress" && $0.remaining != nil }
            }), let fetched = cards.map(\.refreshedAt).min() else { continue }
            state.finish(family: family, outcome: .success, now: fetched)
            errors[family] = nil
            changed = true
        }
        if changed { _ = saveSchedule() }
    }

    func checkCompetitors() {
        let others = competitors()
        conflict = others.isEmpty ? nil : "Studio polling is paused while \(others.joined(separator: ", ")) is running. Close the other tracker to resume."
    }

    func poll(snapshots: [StudioSnapshot]) async -> String {
        guard !isPolling else { return "A provider check is already running." }
        checkCompetitors()
        guard active else { return conflict ?? problem ?? "Provider polling is disabled for this preview." }
        let families = ["claude", "codex"].filter { family in snapshots.contains { $0.family == family } }
        guard !families.isEmpty else { return "No Claude or Codex accounts are available. Use Account Setup to connect them." }
        let now = clock()
        for family in families where state.records[family] == nil {
            if snapshots.contains(where: { $0.family == family && $0.waitsForProvider }) {
                state.seedCachedWait(family: family, now: now)
                if let hint = snapshots.filter({ $0.family == family }).compactMap({ $0.warning.flatMap(studioRetryHint) }).max(),
                   hint > 900 {
                    state.records[family]?.nextAttempt = now.addingTimeInterval(hint)
                    state.records[family]?.providerRetryAfter = now.addingTimeInterval(hint)
                }
            } else if let latest = snapshots.filter({ $0.family == family }).map(\.refreshedAt).max(), latest > now.addingTimeInterval(-300), latest <= now.addingTimeInterval(60) {
                state.records[family] = StudioPollRecord(lastAttempt: latest, nextAttempt: latest.addingTimeInterval(300),
                                                        consecutiveFailures: 0, providerRetryAfter: nil)
            }
        }
        guard saveSchedule() else { return problem ?? "Polling schedule unavailable." }
        let due = families.filter { state.canAttempt(family: $0, now: now) }
        guard !due.isEmpty else { return scheduleSummary(now: now) }
        isPolling = true
        defer { isPolling = false }
        var refreshed: [String] = []
        for family in due {
            guard !Task.isCancelled else { break }
            checkCompetitors()
            guard active else { break }
            let started = clock()
            guard state.begin(family: family, now: started), saveSchedule() else { break }
            message = "Checking \(family.capitalized)…"
            let result = await client.refresh(providerID: family)
            var cached = (try? readCache()) ?? snapshots
            // Confirm publication of the exact engine-reported timestamp before declaring success.
            for _ in 0..<20 where !StudioRefreshPlan.cacheHasReportedReadings(cached, reported: result.fetchedAtByProvider) {
                if Task.isCancelled { break }
                try? await Task.sleep(for: .milliseconds(250))
                cached = (try? readCache()) ?? cached
            }
            let cards = cached.filter { $0.family == family }
            let blocked = cards.contains { $0.waitsForProvider }
            let cacheReceived = StudioRefreshPlan.cacheHasReportedReadings(cached, reported: result.fetchedAtByProvider)
            let fresh = cacheReceived && !result.fetchedAtByProvider.isEmpty && result.failedProviderIDs.isEmpty
                && result.warning == nil && result.fetchedAtByProvider.allSatisfy { id, date in
                    date >= started.addingTimeInterval(-1) && cards.contains { card in
                        card.id == id && abs(card.refreshedAt.timeIntervalSince(date)) < 1 && !card.isStale(now: clock()) && card.warning == nil && card.loginRequired != true
                            && card.lines.contains { $0.type == "progress" && $0.remaining != nil }
                    }
                }
            if blocked && result.error == nil {
                let hint = cards.compactMap { $0.warning.flatMap(studioRetryHint) }.max()
                state.finish(family: family, outcome: .rateLimited(retryAfter: hint), now: clock())
                errors[family] = "Provider rate limit; Studio will retry after its cooldown."
            } else if result.succeeded && fresh {
                state.finish(family: family, outcome: .success, now: clock())
                errors[family] = nil
                refreshed.append(family.capitalized)
            } else {
                state.finish(family: family, outcome: .failure, now: clock())
                errors[family] = result.error ?? result.warning ?? "No fresh provider reading was received."
            }
            guard saveSchedule() else { break }
        }
        message = refreshed.isEmpty ? scheduleSummary(now: clock())
            : "Updated \(refreshed.joined(separator: " and ")). \(scheduleSummary(now: clock()))"
        return message
    }

    func scheduleSummary(now: Date) -> String {
        ["claude", "codex"].compactMap { family -> String? in
            guard let next = nextAttempt(family: family) else { return nil }
            return "\(family.capitalized) \(hasFailure(family: family) ? "retry" : "check") \(next > now ? "in " + StudioFormat.interval(next, now: now) : "due")"
        }.joined(separator: " · ")
    }

    func publish(snapshots: [StudioSnapshot], stale: (StudioSnapshot) -> Bool, now: Date) {
        guard !suppressed else { return }
        var providers: [String: Any] = [:]
        for snapshot in snapshots {
            var resources: [String: Any] = [:]
            for line in snapshot.lines where line.type == "progress" {
                var resource: [String: Any] = ["kind": "consumption", "unit": "percent"]
                if let used = line.used { resource["used"] = used }
                if let limit = line.limit { resource["limit"] = limit }
                if let reset = line.resetsAt { resource["resetsAt"] = Self.stamp(reset) }
                resources[line.label.lowercased().replacingOccurrences(of: " ", with: "_")] = resource
            }
            providers[snapshot.id] = ["displayName": snapshot.displayName, "fetchedAt": Self.stamp(snapshot.refreshedAt),
                                       "stale": stale(snapshot), "resources": resources]
        }
        let payload: [String: Any] = ["connected": active, "observedAt": Self.stamp(now), "providers": providers,
            "errors": snapshots.compactMap { card -> [String: String]? in
                guard let error = errors[card.family] else { return nil }
                return ["providerId": card.id, "message": error]
            }, "nextAttempts": state.records.mapValues { Self.stamp(max($0.nextAttempt, $0.providerRetryAfter ?? .distantPast)) }]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: root.appendingPathComponent("latest-state.json"), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: root.appendingPathComponent("latest-state.json").path)
        } catch { fail("Studio's local status file could not be saved. \(error.localizedDescription)") }
    }

    private func saveSchedule() -> Bool {
        guard problem == nil else { return false }
        do {
            try JSONEncoder().encode(state).write(to: scheduleURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scheduleURL.path)
            return true
        } catch { fail("Polling is paused because its schedule could not be saved. \(error.localizedDescription)"); return false }
    }
    private func fail(_ text: String) { problem = text; logger.error("\(text, privacy: .public)") }
    private static func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
