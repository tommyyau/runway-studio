import Foundation

/// Persisted per-family scheduling state. The coordinator serializes attempts and persists changes.
struct StudioPollState: Codable, Equatable, Sendable {
    var records: [String: StudioPollRecord] = [:]

    /// A cached wait warning without prior state starts one finite cooldown, once per family.
    mutating func seedCachedWait(family: String, now: Date) {
        guard records[family] == nil else { return }
        records[family] = StudioPollRecord(lastAttempt: nil, nextAttempt: now.addingTimeInterval(900),
                                           consecutiveFailures: 1, providerRetryAfter: nil)
    }

    func nextAllowed(family: String) -> Date? {
        guard let record = records[family] else { return nil }
        return max(record.nextAttempt, record.providerRetryAfter ?? .distantPast)
    }

    func canAttempt(family: String, now: Date) -> Bool {
        nextAllowed(family: family).map { now >= $0 } ?? true
    }

    /// Call immediately before launching either a manual or automatic attempt, and persist it.
    /// Returns false for both callers during the same cooldown. The coordinator owns overlap exclusion.
    @discardableResult
    mutating func begin(family: String, now: Date) -> Bool {
        guard canAttempt(family: family, now: now) else { return false }
        var record = records[family] ?? StudioPollRecord(lastAttempt: nil, nextAttempt: now,
                                                          consecutiveFailures: 0, providerRetryAfter: nil)
        record.lastAttempt = now
        // If the process quits mid-attempt, reserve a conservative 15-minute cooldown.
        record.nextAttempt = max(record.nextAttempt, now.addingTimeInterval(900))
        records[family] = record
        return true
    }

    /// Call for the actual provider outcome, never for a cache-only repaint.
    mutating func finish(family: String, outcome: StudioPollOutcome, now: Date) {
        var record = records[family] ?? StudioPollRecord(lastAttempt: nil, nextAttempt: now,
                                                          consecutiveFailures: 0, providerRetryAfter: nil)
        switch outcome {
        case .success:
            record.consecutiveFailures = 0
            record.nextAttempt = now.addingTimeInterval(300)
        case .failure, .rateLimited:
            record.consecutiveFailures = min(32, max(0, record.consecutiveFailures) + 1)
            let exponent = min(3, record.consecutiveFailures - 1)
            let delay = min(7200.0, 900.0 * pow(2, Double(exponent)))
            record.nextAttempt = now.addingTimeInterval(delay)
            if case .rateLimited(let retryAfter) = outcome, let retryAfter, retryAfter.isFinite, retryAfter > 0 {
                let deadline = now.addingTimeInterval(retryAfter)
                record.providerRetryAfter = max(record.providerRetryAfter ?? .distantPast, deadline)
            }
        }
        if let providerDeadline = record.providerRetryAfter {
            if providerDeadline > now { record.nextAttempt = max(record.nextAttempt, providerDeadline) }
            else { record.providerRetryAfter = nil }
        }
        records[family] = record
    }
}

struct StudioPollRecord: Codable, Equatable, Sendable {
    var lastAttempt: Date?
    var nextAttempt: Date
    var consecutiveFailures: Int
    /// Retained separately so a successful outcome cannot erase a later provider deadline.
    var providerRetryAfter: Date?
}

enum StudioPollOutcome: Equatable, Sendable {
    case success
    case rateLimited(retryAfter: TimeInterval?)
    case failure
}

/// Parse only Runway's own rounded retry warning, leaving unknown text unspecified.
func studioRetryHint(_ warning: String) -> TimeInterval? {
    let pattern = #"Retrying in ~([0-9]+)m"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = regex.firstMatch(in: warning, range: NSRange(warning.startIndex..., in: warning)),
          let range = Range(match.range(at: 1), in: warning),
          let minutes = Double(warning[range]), minutes.isFinite, minutes > 0,
          (minutes * 60).isFinite else { return nil }
    return minutes * 60
}
