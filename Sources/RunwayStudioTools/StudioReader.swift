import Foundation

struct Meter: Codable {
    let label: String
    let used: Double?
    let limit: Double?
    let resetsAt: String?
    var source: String = "cache"
    var remainingPercent: Double? {
        guard let used, used.isFinite, let limit, limit.isFinite, limit > 0 else { return nil }
        return max(0, min(100, (1 - used / limit) * 100))
    }
    func available(now: Date) -> Bool {
        guard let remainingPercent, remainingPercent > 0 else { return false }
        if let resetsAt {
            guard let reset = parseDate(resetsAt), reset > now else { return false }
        }
        return true
    }
}
struct Day: Codable {
    let date: String
    let totalTokens: Int?
    let costUSD: Double?
    let costsIncomplete: Bool
}
struct Card: Codable {
    let providerID: String
    let displayName: String
    let fetchedAt: String
    let stale: Bool
    let meters: [Meter]
    let localUsage: [Day]?
    var liveMeters: [Meter]? = nil
    var liveFetchedAt: String? = nil
    var accountScope: String = "Tracker card; account identity not independently verified"
}
struct Report: Codable {
    let connected: Bool
    let source: String
    let observedAt: String
    let cards: [Card]
    let message: String?
    var nextAttempts: [String: String] = [:]
}
func parseDate(_ value: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = f.date(from: value) { return date }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: value)
}
func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

struct StudioReader {
    var cacheURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/com.mattstallone.runway.plist")
    var studioURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/RunwayStudio/latest-state.json")
    var fetch: () async throws -> Data = {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:6736/v1/limits")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
    func read(now: Date = Date()) async -> Report {
        if FileManager.default.fileExists(atPath: studioURL.path) {
            return readStudio(now: now)
        }
        return await readLegacy(now: now)
    }

    private func readStudio(now: Date) -> Report {
        func unavailable(_ message: String) -> Report {
            Report(connected: false, source: "studio_state_unavailable", observedAt: stamp(now), cards: [], message: message)
        }
        do {
            let data = try Data(contentsOf: studioURL)
            guard let state = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let connected = state["connected"] as? Bool,
                  let observed = state["observedAt"] as? String, let observedDate = parseDate(observed),
                  let providers = state["providers"] as? [String: [String: Any]],
                  let errors = state["errors"] as? [[String: Any]],
                  let nextAttempts = state["nextAttempts"] as? [String: String],
                  nextAttempts.values.allSatisfy({ parseDate($0) != nil }),
                  errors.allSatisfy({ $0["providerId"] is String }) else {
                return unavailable("Studio's local state is invalid. Open Studio and allow it to refresh.")
            }
            guard now.timeIntervalSince(observedDate) <= 90, observedDate <= now.addingTimeInterval(60) else {
                return unavailable("Studio's local state has expired. Open Studio and allow it to refresh.")
            }
            let errorIDs = Set(errors.compactMap { $0["providerId"] as? String })
            var cards: [Card] = []
            for (id, live) in providers.sorted(by: { $0.key < $1.key }) {
                guard let name = live["displayName"] as? String,
                      let fetched = live["fetchedAt"] as? String, let date = parseDate(fetched),
                      let reportedStale = live["stale"] as? Bool,
                      let resources = live["resources"] as? [String: [String: Any]] else {
                    return unavailable("Studio's local state is invalid. Open Studio and allow it to refresh.")
                }
                guard ["claude", "codex"].contains(String(id.split(separator: "@").first ?? "")) else { continue }
                let stale = !connected || reportedStale || errorIDs.contains(id) || now.timeIntervalSince(date) > 360 || date > now.addingTimeInterval(60)
                let meters: [Meter] = resources.keys.sorted().compactMap { key in
                    guard let resource = resources[key], resource["kind"] as? String == "consumption" else { return nil }
                    let label = key.replacingOccurrences(of: "_", with: " ").capitalized
                    return Meter(label: label, used: resource["used"] as? Double, limit: resource["limit"] as? Double,
                                 resetsAt: resource["resetsAt"] as? String, source: "studio")
                }
                cards.append(Card(providerID: id, displayName: name, fetchedAt: fetched, stale: stale, meters: meters,
                                  localUsage: cachedUsage(id: id), liveMeters: meters, liveFetchedAt: fetched,
                                  accountScope: "Studio tracker card; local usage spans accounts"))
            }
            return Report(connected: connected, source: "studio_state", observedAt: observed, cards: cards,
                          message: connected ? nil : "Studio polling is inactive; readings are unavailable.", nextAttempts: nextAttempts)
        } catch {
            return unavailable("Studio's local state cannot be read. Open Studio and allow it to refresh.")
        }
    }

    private func cachedUsage(id: String) -> [Day]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let blob = plist["runway.providerSnapshots.v9"] as? Data,
              let cache = try? JSONSerialization.jsonObject(with: blob) as? [String: Any],
              let snapshots = cache["snapshots"] as? [String: [String: Any]],
              let history = snapshots[id]?["usageHistory"] as? [String: Any],
              let series = history["series"] as? [String: Any], let rows = series["daily"] as? [[String: Any]] else { return nil }
        let unknown = history["unknownModelsByDay"] as? [String: [String]] ?? [:]
        return rows.compactMap { row in
            guard let day = row["date"] as? String else { return nil }
            let tokens = row["totalTokens"] as? Int, cost = row["costUSD"] as? Double
            return Day(date: day, totalTokens: tokens, costUSD: cost,
                       costsIncomplete: !(unknown[day] ?? []).isEmpty || ((tokens ?? 0) > 0 && cost == nil))
        }
    }

    private func readLegacy(now: Date) async -> Report {
        var enabled: Set<String>?
        var errors = Set<String>()
        var liveProviders: [String: [String: Any]] = [:]
        do {
            let data = try await fetch()
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let providers = object["providers"] as? [String: Any] else { throw URLError(.badServerResponse) }
            enabled = Set(providers.keys)
            liveProviders = providers.compactMapValues { $0 as? [String: Any] }
            for error in object["errors"] as? [[String: Any]] ?? [] {
                if let id = error["providerId"] as? String { errors.insert(id) }
            }
        } catch { /* Offline is represented in the report. */ }
        do {
            let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: cacheURL), format: nil)
            guard let dictionary = plist as? [String: Any], let data = dictionary["runway.providerSnapshots.v9"] as? Data,
                  let cache = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let snapshots = cache["snapshots"] as? [String: [String: Any]] else { throw URLError(.cannotDecodeContentData) }
            let cards = snapshots.values.compactMap { raw -> Card? in
                guard let id = raw["providerID"] as? String, let name = raw["displayName"] as? String,
                      let fetched = raw["refreshedAt"] as? String, let date = parseDate(fetched),
                      ["claude", "codex"].contains(String(id.split(separator: "@").first ?? "")),
                      enabled?.contains(id) ?? true else { return nil }
                let live = liveProviders[id]
                let liveDate = (live?["fetchedAt"] as? String).flatMap(parseDate)
                let sameSecond = liveDate.map { floor($0.timeIntervalSince1970) == floor(date.timeIntervalSince1970) } ?? false
                let stale = enabled == nil || !sameSecond || (live?["stale"] as? Bool != false) || errors.contains(id) || (raw["loginRequired"] as? Bool == true)
                    || (raw["warning"] as? String != nil) || now.timeIntervalSince(date) > 360 || date > now.addingTimeInterval(60)
                let meters = (raw["lines"] as? [[String: Any]] ?? []).compactMap { line -> Meter? in
                    guard line["type"] as? String == "progress", let label = line["label"] as? String else { return nil }
                    return Meter(label: label, used: line["used"] as? Double, limit: line["limit"] as? Double, resetsAt: line["resetsAt"] as? String)
                }
                let history = raw["usageHistory"] as? [String: Any]
                let series = history?["series"] as? [String: Any]
                let unknownModels = history?["unknownModelsByDay"] as? [String: [String]] ?? [:]
                let days = (series?["daily"] as? [[String: Any]])?.compactMap { day -> Day? in
                    guard let date = day["date"] as? String else { return nil }
                    let tokens = day["totalTokens"] as? Int
                    let cost = day["costUSD"] as? Double
                    let incomplete = !(unknownModels[date] ?? []).isEmpty || ((tokens ?? 0) > 0 && cost == nil)
                    return Day(date: date, totalTokens: tokens, costUSD: cost, costsIncomplete: incomplete)
                }
                let resources = live?["resources"] as? [String: [String: Any]] ?? [:]
                let liveMeters: [Meter] = [("session", "Session"), ("weekly", "Weekly")].compactMap { key, label in
                    guard let resource = resources[key], resource["kind"] as? String == "consumption" else { return nil }
                    return Meter(label: label, used: resource["used"] as? Double, limit: resource["limit"] as? Double,
                                 resetsAt: resource["resetsAt"] as? String, source: "live")
                }
                // The cache timestamp is only second-precision and cannot establish equality of values.
                // Use the live resource itself whenever its card is fresh; retain other lines as cached.
                let displayedMeters = stale ? meters : meters.filter { cached in
                    !liveMeters.contains { $0.label == cached.label }
                } + liveMeters
                return Card(providerID: id, displayName: name, fetchedAt: fetched, stale: stale, meters: displayedMeters,
                            localUsage: days, liveMeters: liveMeters, liveFetchedAt: live?["fetchedAt"] as? String)
            }.sorted { $0.providerID < $1.providerID }
            return Report(connected: enabled != nil, source: "runway_snapshot_cache_and_loopback_api", observedAt: stamp(now), cards: cards,
                          message: enabled == nil ? "Runway is offline; cached values may belong to a previous account." : nil)
        } catch {
            return Report(connected: enabled != nil, source: "unavailable", observedAt: stamp(now), cards: [],
                          message: "Runway's snapshot cache is unavailable. Open Runway and allow it to refresh.")
        }
    }
}

// A family selection must identify one card; never choose an account on the caller's behalf.
func matchingCard(_ report: Report, provider: String) -> Card? {
    if let exact = report.cards.first(where: { $0.providerID == provider }) { return exact }
    let matches = report.cards.filter { $0.providerID.split(separator: "@").first.map(String.init) == provider }
    return matches.count == 1 ? matches[0] : nil
}
func allowanceAvailable(_ report: Report, provider: String, metric: String, now: Date) -> Bool {
    guard report.connected, let card = matchingCard(report, provider: provider), !card.stale,
          let meter = card.liveMeters?.first(where: { $0.label.caseInsensitiveCompare(metric) == .orderedSame }) else { return false }
    return meter.available(now: now)
}
