import Foundation
import OSLog
import Observation

/// Public vendor-wide status, independent of local credentials or subscription state.
struct StudioServiceStatus: Equatable, Sendable {
    let provider: String
    let description: String
    let indicator: String
    let checkedAt: Date
    var failedAt: Date?

    var isStale: Bool { failedAt != nil }
    var statusURL: URL {
        URL(string: provider == "claude" ? "https://status.claude.com/" : "https://status.openai.com/")!
    }
}

actor StudioServiceStatusMonitor {
    static let shared = StudioServiceStatusMonitor()
    private let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private var cache: [String: StudioServiceStatus] = [:]
    private var lastAttempt: [String: Date] = [:]
    private let interval: TimeInterval
    private let logger = Logger(subsystem: "com.runway.studio", category: "service-status")

    init(interval: TimeInterval = 300,
         fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
             let configuration = URLSessionConfiguration.ephemeral
             configuration.httpShouldSetCookies = false
             configuration.urlCredentialStorage = nil
             let session = URLSession(configuration: configuration)
             defer { session.finishTasksAndInvalidate() }
             return try await session.data(for: request)
         }) {
        self.interval = interval
        self.fetch = fetch
    }

    func status(provider: String, now: Date = Date()) async -> StudioServiceStatus? {
        guard provider == "claude" || provider == "codex" else { return nil }
        if let attempted = lastAttempt[provider], now.timeIntervalSince(attempted) < interval {
            return cache[provider]
        }
        lastAttempt[provider] = now
        let host = provider == "claude" ? "status.claude.com" : "status.openai.com"
        var request = URLRequest(url: URL(string: "https://\(host)/api/v2/summary.json")!)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await fetch(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw StatusError.invalidResponse
            }
            let payload = try JSONDecoder().decode(Summary.self, from: data)
            guard !payload.status.description.isEmpty, !payload.status.indicator.isEmpty else {
                throw StatusError.invalidResponse
            }
            let value = StudioServiceStatus(provider: provider, description: payload.status.description,
                indicator: payload.status.indicator, checkedAt: now, failedAt: nil)
            cache[provider] = value
            return value
        } catch {
            logger.error("Public status fetch failed for \(provider, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if var previous = cache[provider] {
                previous.failedAt = now
                cache[provider] = previous
                return previous
            }
            return nil
        }
    }

    private struct Summary: Decodable {
        struct Status: Decodable { let indicator: String; let description: String }
        let status: Status
    }
    private enum StatusError: Error { case invalidResponse }
}

@MainActor @Observable
final class StudioServiceStatusStore {
    private(set) var statuses: [String: StudioServiceStatus] = [:]
    private(set) var checked = false
    private let monitor: StudioServiceStatusMonitor
    private var refreshing = false

    init(monitor: StudioServiceStatusMonitor = .shared) { self.monitor = monitor }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        async let claude = monitor.status(provider: "claude")
        async let codex = monitor.status(provider: "codex")
        let (c, o) = await (claude, codex)
        statuses = ["claude": c, "codex": o].compactMapValues { $0 }
        checked = true
    }
}
