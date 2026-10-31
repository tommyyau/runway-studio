import Foundation

/// Public bridge from the mature local-log parsers to the Studio dashboard. No credential readers
/// or provider clients are constructed. The separate cache namespace prevents older app builds
/// from replacing metadata-rich parsed records with their older cache schema.
public actor LocalActivityReader {
    private let claude: ClaudeLogUsageScanner
    private let codex: CodexLogUsageScanner

    public init() {
        claude = ClaudeLogUsageScanner(incrementalScanner: IncrementalJSONLScanner(
            logTag: LogTag.plugin("claude-activity"),
            persistence: JSONLScanCachePersistence(namespace: "studio-claude", schemaVersion: 3)))
        codex = CodexLogUsageScanner(incrementalScanner: IncrementalJSONLScanner(
            logTag: LogTag.plugin("codex-activity"),
            persistence: JSONLScanCachePersistence(namespace: "studio-codex", schemaVersion: 2)))
    }

    public func scan(now: Date = Date()) async -> [LocalActivityEvent] {
        async let claudeEntries = claude.scanEvents(now: now)
        async let codexEntries = codex.scanEvents(now: now)
        let (c, o) = await (claudeEntries, codexEntries)
        let since = JSONLScanning.sinceDate(daysBack: 30, now: now)
        var result: [LocalActivityEvent] = []
        for entry in c ?? [] where entry.timestamp >= since && entry.timestamp <= now {
            result.append(LocalActivityEvent(claude: entry))
        }
        for event in CodexLogUsageScanner.deduplicatedEvents(o ?? []) where event.timestamp >= since && event.timestamp <= now {
            result.append(LocalActivityEvent(codex: event))
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }
}

public struct LocalActivityEvent: Codable, Sendable {
    public var provider: String
    public var timestamp: Date
    public var model: String
    public var source: String
    public var cwd: String?
    public var sessionID: String?
    public var agentID: String?
    public var agentRole: String
    public var agentName: String?
    public var input: Int
    public var cached: Int
    public var output: Int
    public var unclassified: Int
}

extension LocalActivityEvent {
    init(claude entry: ClaudeLogUsageScanner.Entry) {
        self.init(provider: "claude", timestamp: entry.timestamp,
            model: entry.model ?? "Unattributed", source: entry.source ?? "Unknown Claude Source", cwd: entry.activity?.cwd,
            sessionID: entry.activity?.sessionID, agentID: entry.activity?.agentID,
            agentRole: entry.activity?.role ?? "Unknown Agent", agentName: entry.activity?.name,
            input: entry.tokens.input + entry.tokens.cacheWrite5m + entry.tokens.cacheWrite1h,
            cached: entry.tokens.cacheRead, output: entry.tokens.output, unclassified: 0)
    }

    init(codex event: CodexLogUsageScanner.Event) {
        self.init(provider: "codex", timestamp: event.timestamp,
            model: event.model, source: "Codex Local Sessions", cwd: event.activity?.cwd,
            sessionID: event.activity?.sessionID, agentID: event.activity?.agentID,
            agentRole: event.activity?.role ?? "Unknown Agent", agentName: event.activity?.name,
            input: max(0, event.input - event.cached), cached: event.cached, output: event.output,
            unclassified: max(0, event.total - event.input - event.output))
    }
}
