import Foundation
import Runway

struct ActivityTokens: Codable, Equatable, Sendable {
    var input = 0
    var cached = 0
    var output = 0
    var unclassified = 0
    var total: Int { input + cached + output + unclassified }
    var newOnly: Int { input + output }
    mutating func add(_ other: Self) {
        input += other.input; cached += other.cached
        output += other.output; unclassified += other.unclassified
    }
    func value(newOnly: Bool) -> Int { newOnly ? self.newOnly : total }
}

struct ActivityEvent: Codable, Sendable {
    var provider: String
    var timestamp: Date
    var project: String
    var projectPath: String
    var session: String
    var agentID: String
    var agentRole: String
    var agentName: String
    var model: String
    var tokens: ActivityTokens
    var source: String = "Unknown Source"
}

/// Resolves worktrees through Git's on-disk metadata, without running repository code or commands.
struct ActivityProjectResolver {
    private var memo: [String: (String, String)] = [:]
    var workspaceRoots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("repos", isDirectory: true)]
    mutating func resolve(_ cwd: String?) -> (name: String, path: String) {
        guard let cwd, cwd.hasPrefix("/") else { return ("Unknown Project", "Working directory not recorded") }
        if let cached = memo[cwd] { return cached }
        let url = URL(fileURLWithPath: cwd).standardizedFileURL.resolvingSymlinksInPath()
        var candidate = url
        while candidate.path != "/" {
            let git = candidate.appendingPathComponent(".git")
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: git.path, isDirectory: &directory) {
                var root = candidate
                if !directory.boolValue,
                   let text = try? String(contentsOf: git, encoding: .utf8), text.hasPrefix("gitdir:") {
                    let relative = text.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
                    let gitdir = URL(fileURLWithPath: relative, isDirectory: true, relativeTo: candidate).standardizedFileURL
                    if let common = try? String(contentsOf: gitdir.appendingPathComponent("commondir"), encoding: .utf8) {
                        let commonURL = URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines),
                                            isDirectory: true, relativeTo: gitdir).standardizedFileURL.resolvingSymlinksInPath()
                        if commonURL.lastPathComponent == ".git" { root = commonURL.deletingLastPathComponent() }
                    }
                }
                let result = (root.lastPathComponent, root.path)
                memo[cwd] = result
                return result
            }
            candidate.deleteLastPathComponent()
        }
        let workspaceProject = workspaceRoots.compactMap { root -> URL? in
            let path = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
            guard url.path.hasPrefix(path), let folder = url.path.dropFirst(path.count).split(separator: "/").first else { return nil }
            return root.appendingPathComponent(String(folder), isDirectory: true)
        }.first
        let project = workspaceProject ?? url
        let result = (project.lastPathComponent, project.path)
        memo[cwd] = result
        return result
    }
}

actor StudioActivityIndex {
    private let reader = LocalActivityReader()
    private var resolver = ActivityProjectResolver()

    func scan(now: Date) async -> [ActivityEvent] {
        let events = await reader.scan(now: now)
        return events.map { raw in
            let project = resolver.resolve(raw.cwd)
            let session = raw.sessionID ?? "Unknown Session"
            let id = raw.agentID ?? raw.sessionID ?? "unknown"
            return ActivityEvent(provider: raw.provider, timestamp: raw.timestamp,
                project: project.name, projectPath: project.path,
                session: session, agentID: id, agentRole: raw.agentRole,
                agentName: raw.agentName ?? "\(raw.agentRole) · \(id.prefix(12))", model: raw.model,
                tokens: ActivityTokens(input: raw.input, cached: raw.cached, output: raw.output, unclassified: raw.unclassified),
                source: raw.source)
        }
    }
}

enum ActivityResolution: String, CaseIterable {
    case fiveMinutes = "5 Minutes", hourly = "Hourly", daily = "Daily"

    func dateInterval(for date: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .fiveMinutes:
            guard let hour = calendar.dateInterval(of: .hour, for: date) else { return nil }
            let offset = floor(date.timeIntervalSince(hour.start) / 300) * 300
            return DateInterval(start: hour.start.addingTimeInterval(offset), duration: 300)
        case .hourly: return calendar.dateInterval(of: .hour, for: date)
        case .daily: return calendar.dateInterval(of: .day, for: date)
        }
    }
}
enum ActivityGrouping: String, CaseIterable {
    case project = "By Project", agent = "By Agent", model = "By Model", source = "By Source"
}

struct ActivityBucket: Identifiable {
    var start: Date
    var end: Date
    var tokens = ActivityTokens()
    var id: Date { start }
}
struct ActivityGroup: Identifiable {
    var id: String
    var title: String
    var detail: String
    var tokens = ActivityTokens()
    var children: [ActivityGroup] = []
}
struct ActivityReport {
    var buckets: [ActivityBucket] = []
    var groups: [ActivityGroup] = []
    var totals = ActivityTokens()
    var selectedInterval: DateInterval

    static func interval(days: Int, now: Date, calendar: Calendar = .current) -> DateInterval {
        let start = days == 1 ? now.addingTimeInterval(-86400)
            : calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        return DateInterval(start: start, end: now)
    }

    static func build(events: [ActivityEvent], provider: String, interval: DateInterval,
                      resolution: ActivityResolution, grouping: ActivityGrouping,
                      selection: ClosedRange<Date>? = nil, newOnly: Bool = false,
                      calendar: Calendar = .current) -> Self {
        var selected = interval
        if let selection {
            let start = min(interval.end, max(interval.start, selection.lowerBound))
            // Include an event exactly on the selected upper boundary.
            let end = min(interval.end, selection.upperBound.addingTimeInterval(0.000_001))
            selected = DateInterval(start: start, end: max(start, end))
        }
        var report = Self(selectedInterval: selected)
        var buckets: [Date: ActivityBucket] = [:]
        var groups: [String: ActivityGroup] = [:]
        var agents: [String: [String: ActivityGroup]] = [:]
        for event in events where event.provider == provider && event.timestamp >= interval.start && event.timestamp < interval.end {
            guard let bin = resolution.dateInterval(for: event.timestamp, calendar: calendar) else { continue }
            var bucket = buckets[bin.start] ?? ActivityBucket(start: bin.start, end: bin.end)
            bucket.tokens.add(event.tokens); buckets[bin.start] = bucket
            guard event.timestamp >= selected.start, event.timestamp < selected.end else { continue }
            report.totals.add(event.tokens)
            let key: String; let title: String; let detail: String
            switch grouping {
            case .project: key = event.projectPath; title = event.project; detail = event.projectPath
            case .agent: key = event.agentRole; title = event.agentRole; detail = "Recorded agent roles"
            case .model: key = event.model; title = event.model; detail = "Recorded model"
            case .source: key = event.source; title = event.source; detail = "Local records"
            }
            var group = groups[key] ?? ActivityGroup(id: key, title: title, detail: detail)
            group.tokens.add(event.tokens); groups[key] = group
            if grouping == .agent {
                let childKey = event.projectPath + ":" + event.agentID
                var child = agents[key]?[childKey] ?? ActivityGroup(id: childKey, title: event.agentName, detail: event.project)
                child.tokens.add(event.tokens); agents[key, default: [:]][childKey] = child
            }
        }
        report.buckets = buckets.values.sorted { $0.start < $1.start }
        report.groups = groups.values.map { group in
            var group = group
            group.children = (agents[group.id].map { Array($0.values) } ?? [])
                .sorted { $0.tokens.value(newOnly: newOnly) > $1.tokens.value(newOnly: newOnly) }
            return group
        }.sorted { $0.tokens.value(newOnly: newOnly) > $1.tokens.value(newOnly: newOnly) }
        return report
    }
}
