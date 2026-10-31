import Foundation

/// Pure event evaluator. Persisted account stamps and delivery keys survive restarts. A first
/// observation establishes a baseline rather than fabricating a recovery, reset or drop.
struct StudioAlertEngine: Codable, Equatable {
    var accounts: [String: StudioAlertAccountState] = [:]
    var acknowledged: [String: Date] = [:]
    var pending: [StudioAlertEvent] = []

    mutating func evaluate(_ observations: [StudioAlertObservation], now: Date,
                           preferences p: StudioAlertPreferences) -> [StudioAlertEvent] {
        let oldest = now.addingTimeInterval(-70 * 86400)
        acknowledged = acknowledged.filter { $0.value >= oldest }
        accounts = accounts.filter { $0.value.previous.fetchedAt >= oldest }
        pending.removeAll { now.timeIntervalSince($0.createdAt) > 1800 || $0.createdAt > now.addingTimeInterval(60) }
        guard p.enabled else {
            pending.removeAll()
            for observation in observations where observation.fresh {
                accounts[observation.account] = StudioAlertAccountState(previous: observation)
            }
            return []
        }
        let activeAccounts = Set(observations.map(\.account))
        pending.removeAll { $0.kind != .morning && !activeAccounts.contains($0.account) }
        for observation in observations {
            process(observation, now: now, preferences: p)
        }
        if p.morning, let day = Self.morningDay(now: now, preferences: p) {
            enqueue(StudioAlertEvent(id: "morning:\(p.timeZoneID):\(day)", account: "morning", kind: .morning,
                title: "Runway Studio Morning Report",
                body: StudioAlertText.morning(observations, now: now, preferences: p), createdAt: now))
        }
        pending.removeAll { event in
            switch event.kind {
            case .morning: return !p.morning || Self.morningDay(now: now, preferences: p) == nil
            case .low: return !p.lowAllowance
            case .forecast: return !p.forecast
            case .recovery: return !p.recovery
            case .reset: return !p.resetChanges
            case .expiry: return !p.expiry
            case .spare: return !p.spare
            case .drop: return !((accounts[event.account]?.previous.family == "claude" ? p.claudeDrop : p.codexDrop).enabled)
            case .test: return false
            }
        }
        for index in pending.indices where pending[index].kind == .morning {
            pending[index].body = StudioAlertText.morning(observations, now: now, preferences: p)
        }
        return pending.filter { event in
            guard event.kind != .morning else { return true }
            guard let observation = observations.first(where: { $0.account == event.account }), observation.fresh,
                  now.timeIntervalSince(observation.fetchedAt) <= 360,
                  observation.fetchedAt <= now.addingTimeInterval(60) else { return false }
            switch event.kind {
            case .forecast:
                guard let weekly = observation.weekly, event.id.hasPrefix("\(observation.account):\(weekly.windowKey):") else { return false }
                return weekly.exhaustion(now: now) != nil
            case .low:
                let meter = event.id.contains(":low:weekly:") ? observation.weekly : observation.session
                return meter.map { $0.remaining <= 10 && $0.reset > now && event.id.hasSuffix($0.windowKey) } ?? false
            case .recovery: return !observation.blocked
            case .expiry: return observation.expiries.contains { $0 > now && event.id.contains(String(Int($0.timeIntervalSince1970.rounded()))) }
            case .drop, .spare:
                return observation.weekly.map { event.id.hasPrefix("\(observation.account):\($0.windowKey):") } ?? false
            default: return true
            }
        }
    }

    mutating func acknowledge(_ event: StudioAlertEvent, now: Date) {
        acknowledged[event.id] = now
        pending.removeAll { $0.id == event.id }
    }

    private mutating func enqueue(_ event: StudioAlertEvent) {
        guard acknowledged[event.id] == nil, !pending.contains(where: { $0.id == event.id }) else { return }
        pending.append(event)
    }

    private mutating func process(_ current: StudioAlertObservation, now: Date, preferences p: StudioAlertPreferences) {
        guard current.fresh, now.timeIntervalSince(current.fetchedAt) <= 360, current.fetchedAt <= now.addingTimeInterval(60) else {
            if var state = accounts[current.account] {
                if state.unavailableSince == nil { state.unavailableSince = now }
                accounts[current.account] = state
            }
            return
        }
        guard var state = accounts[current.account] else {
            accounts[current.account] = StudioAlertAccountState(previous: current)
            if p.expiry, let event = expiryEvent(current, now: now, preferences: p) { enqueue(event) }
            return
        }
        guard current.fetchedAt > state.previous.fetchedAt else { return }
        let previous = state.previous
        let key = current.account
        let window = current.weekly?.windowKey ?? "unknown"
        let prefix = "\(key):\(window)"
        let rule = current.family == "claude" ? p.claudeDrop : p.codexDrop
        let weeklyChanged = current.weekly?.windowKey != previous.weekly?.windowKey
        var candidates: [StudioAlertEvent] = []
        func event(_ kind: StudioAlertEvent.Kind, _ suffix: String, _ title: String, _ body: String) -> StudioAlertEvent {
            StudioAlertEvent(id: "\(prefix):\(suffix)", account: key, kind: kind,
                             title: title, body: body, createdAt: now)
        }

        // A missing old blocking metric is not proof of recovery.
        let oldBlocked = [(previous.weekly, current.weekly), (previous.session, current.session)]
            .filter { pair in pair.0.map { $0.remaining <= 0 && $0.reset > previous.fetchedAt } ?? false }
        let confirmedRecovery = !oldBlocked.isEmpty && oldBlocked.allSatisfy { pair in
            pair.1.map { $0.remaining > 0 && $0.reset > current.fetchedAt } ?? false
        } && !current.blocked
        if p.recovery, confirmedRecovery {
            let recoveredWindows = oldBlocked.compactMap { $0.0?.windowKey }.joined(separator: ":")
            candidates.append(event(.recovery, "recovery:\(recoveredWindows)", "\(current.name) Has Allowance Again", current.weeklySummary))
        } else if p.recovery, let unavailable = state.unavailableSince, now.timeIntervalSince(unavailable) >= 120 {
            candidates.append(event(.recovery, "readings:\(Int(unavailable.timeIntervalSince1970))",
                "\(current.name) Readings Restored", current.weeklySummary + ". This confirms usage readings, not service health."))
        }
        state.unavailableSince = nil
        if p.resetChanges {
            var changes: [String] = []
            if let before = previous.weekly, let after = current.weekly,
               after.reset.timeIntervalSince(before.reset) > 60, current.fetchedAt < before.reset.addingTimeInterval(-60),
               after.remaining > before.remaining {
                changes.append("Your weekly allowance reset before its previously reported renewal.")
            }
            if let before = previous.credits, let after = current.credits, after > before {
                changes.append("\(after - before) new reset credit\(after - before == 1 ? "" : "s").")
            }
            if !changes.isEmpty {
                candidates.append(event(.reset, "change:\(Int(current.fetchedAt.timeIntervalSince1970))",
                    "\(current.name) Allowance Updated", changes.joined(separator: " ") + " " + current.weeklySummary))
            }
        }
        if p.lowAllowance {
            let low = [("weekly", current.weekly), ("session", current.session)].first {
                $0.1.map { $0.remaining <= 10 && $0.reset > now } ?? false
            }
            if let low, let meter = low.1 {
                candidates.append(event(.low, "low:\(low.0):\(meter.windowKey)", "\(current.name) Allowance Is Low",
                    "\(Int(meter.remaining.rounded()))% of your \(low.0) allowance remains. Resets \(StudioAlertText.date(meter.reset, timeZone: p.timeZoneID))."))
            }
        }
        if weeklyChanged {
            state.samples.removeAll(); state.dropActive = false; state.quietSince = nil
        }
        if let weekly = current.weekly, weekly.reset > now {
            let minutes = min(120, max(5, rule.minutes))
            let points = min(100, max(1, rule.points))
            state.samples.removeAll { current.fetchedAt.timeIntervalSince($0.date) > Double(minutes * 60) }
            if let last = previous.weekly, !weeklyChanged, weekly.remaining < last.remaining { state.quietSince = nil }
            else if state.quietSince == nil { state.quietSince = current.fetchedAt }
            if let quiet = state.quietSince, current.fetchedAt.timeIntervalSince(quiet) >= Double(minutes * 60) {
                state.dropActive = false
            }
            if !weeklyChanged, let before = previous.weekly,
               current.fetchedAt.timeIntervalSince(previous.fetchedAt) <= Double(minutes * 60),
               !state.samples.contains(where: { $0.date == previous.fetchedAt }) {
                state.samples.append(.init(date: previous.fetchedAt, remaining: before.remaining))
            }
            let high = state.samples.map(\.remaining).max() ?? weekly.remaining
            if rule.enabled, high - weekly.remaining >= Double(points), !state.dropActive {
                state.dropActive = true; state.dropEpisode += 1
                candidates.append(event(.drop, "drop:\(state.dropEpisode)", "\(current.name) Allowance Dropped Quickly",
                    "Your weekly allowance fell \(Int((high - weekly.remaining).rounded())) percentage points within \(minutes) minutes. " + current.weeklySummary + ". Local token activity may help investigate; it does not explain every allowance change."))
            }
            state.samples.append(.init(date: current.fetchedAt, remaining: weekly.remaining))
            if p.forecast, weekly.remaining > 10 || !p.lowAllowance,
               let exhaustion = weekly.exhaustion(now: now), weekly.reset.timeIntervalSince(exhaustion) >= 12 * 3600 {
                candidates.append(event(.forecast, "forecast", "\(current.name) May Reach Its Limit Early",
                    "If the average pace so far continues, allowance may run out \(StudioAlertText.date(exhaustion, timeZone: p.timeZoneID)), before renewal \(StudioAlertText.date(weekly.reset, timeZone: p.timeZoneID))."))
            }
            let calendar = Self.calendar(p)
            let hour = calendar.component(.hour, from: now)
            if p.spare, hour >= 8, hour < 20, weekly.reset.timeIntervalSince(now) < 48 * 3600,
               let duration = weekly.duration, duration > 0 {
                let elapsed = now.timeIntervalSince(weekly.reset.addingTimeInterval(-duration))
                if elapsed >= max(60, duration * 0.01) {
                    let projectedLeft = 100 - (100 - weekly.remaining) / elapsed * duration
                    if projectedLeft >= 30 {
                        candidates.append(event(.spare, "spare", "\(current.name) Has Allowance To Spare",
                            "At the average pace so far, about \(Int(projectedLeft.rounded()))% would remain unused at renewal. " + current.weeklySummary))
                    }
                }
            }
        }
        if p.expiry, let expiry = expiryEvent(current, now: now, preferences: p) { candidates.append(expiry) }
        // One notification per account/read. Low allowance and recovery bypass the quiet period.
        if let chosen = candidates.first(where: { candidate in
            acknowledged[candidate.id] == nil && !pending.contains(where: { $0.id == candidate.id })
        }) {
            if chosen.kind == .recovery || chosen.kind == .low || (state.lastAlertAt.map({ now.timeIntervalSince($0) >= 600 }) ?? true) {
                enqueue(chosen); state.lastAlertAt = now
            }
        }
        state.previous = current
        accounts[key] = state
    }

    private func expiryEvent(_ observation: StudioAlertObservation, now: Date, preferences p: StudioAlertPreferences) -> StudioAlertEvent? {
        guard observation.credits != 0 else { return nil }
        for expiry in observation.expiries.sorted() where expiry > now && expiry.timeIntervalSince(now) <= 86400 {
            let stage = expiry.timeIntervalSince(now) <= 7200 ? "2h" : "24h"
            let id = "\(observation.account):expiry:\(Int(expiry.timeIntervalSince1970.rounded())):\(stage)"
            if acknowledged[id] == nil && !pending.contains(where: { $0.id == id }) {
                return StudioAlertEvent(id: id, account: observation.account, kind: .expiry,
                    title: "\(observation.name) Reset Credit Expires Soon",
                    body: "A reset credit expires \(StudioAlertText.date(expiry, timeZone: p.timeZoneID)). Studio will never spend it automatically.", createdAt: now)
            }
        }
        return nil
    }

    static func calendar(_ preferences: StudioAlertPreferences) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: preferences.timeZoneID) ?? .current
        return calendar
    }
    static func morningDay(now: Date, preferences p: StudioAlertPreferences) -> String? {
        let calendar = calendar(p)
        let start = calendar.startOfDay(for: now)
        guard let due = calendar.nextDate(after: start.addingTimeInterval(-1),
            matching: DateComponents(hour: min(23, max(0, p.hour)), minute: min(59, max(0, p.minute))),
            matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              now >= due, now.timeIntervalSince(due) < 4 * 3600 else { return nil }
        return StudioDay.key(now, calendar: calendar)
    }
}
