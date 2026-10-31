import Foundation
import OSLog

struct StudioManualRefreshResult: Sendable {
    let providerID: String
    /// Timestamp reported by the provider engine, not a UI reload time.
    let fetchedAt: Date?
    let fetchedAtByProvider: [String: Date]
    let failedProviderIDs: [String]
    let warning: String?
    let error: String?
    var limitsData: Data? = nil
    var succeeded: Bool { error == nil }
}

struct StudioRefreshProcessOutput: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

enum StudioRefreshProcessError: Error {
    case timedOut, outputTooLarge, cancelled
}

/// Studio’s shared coordinator calls the in-process MIT provider engine. The runner is injectable for tests.
struct StudioManualRefreshClient: Sendable {
    typealias Runner = @Sendable (_ arguments: [String], _ timeout: TimeInterval) async throws -> StudioRefreshProcessOutput
    let runner: Runner
    init(runner: @escaping Runner = { arguments, timeout in try await StudioProviderCache.shared.run(arguments, timeout: timeout) }) { self.runner = runner }


    func refresh(providerID: String) async -> StudioManualRefreshResult {
        func failure(_ message: String) -> StudioManualRefreshResult {
            Logger(subsystem: "local.runway.studio", category: "manual-refresh").error("\(providerID, privacy: .public): \(message, privacy: .public)")
            return StudioManualRefreshResult(providerID: providerID, fetchedAt: nil, fetchedAtByProvider: [:], failedProviderIDs: [], warning: nil, error: message)
        }
        let family = providerID.split(separator: "@", maxSplits: 1).first.map(String.init)
        guard ["claude", "codex"].contains(family ?? ""),
              !providerID.hasPrefix("-"), !providerID.hasSuffix("@") else {
            return failure("This account cannot be refreshed by Studio.")
        }
        do {
            let result = try await runner([providerID, "--force"], 45)
            guard result.stdout.count <= (512 * 1024),
                  result.stderr.count <= (512 * 1024) else { throw StudioRefreshProcessError.outputTooLarge }
            guard result.status == 0 || result.status == 4 else {
                return failure("Studio could not refresh this card (engine result \(result.status)).")
            }
            guard let object = try JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
                  object["schema"] as? String == "runway.limits.v1",
                  let providers = object["providers"] as? [String: [String: Any]],
                  let errors = object["errors"] as? [[String: Any]] else {
                return failure("Studio returned an invalid refresh response.")
            }
            let failed = errors.compactMap { $0["providerId"] as? String }
            var dates: [String: Date] = [:]
            for (id, provider) in providers {
                // A family request can return several cards; never include another family.
                guard id == providerID || (providerID == family && id.hasPrefix(providerID + "@")),
                      !failed.contains(id), let text = provider["fetchedAt"] as? String,
                      let date = Self.parseDate(text), provider["resources"] is [String: Any] else { continue }
                dates[id] = date
            }
            guard !dates.isEmpty else {
                return failure(errors.compactMap { $0["message"] as? String }.first ?? "Studio returned no usable reading. Open Accounts for connection details.")
            }
            return StudioManualRefreshResult(providerID: providerID, fetchedAt: dates[providerID],
                fetchedAtByProvider: dates, failedProviderIDs: failed,
                warning: result.status == 4 || !errors.isEmpty ? "Studio reported a partial refresh; check Accounts for details." : nil,
                error: nil, limitsData: result.stdout)

        } catch StudioRefreshProcessError.timedOut {
            return failure("The provider check timed out.")
        } catch is CancellationError {
            return failure("Refresh cancelled.")
        } catch StudioRefreshProcessError.cancelled {
            return failure("Refresh cancelled.")
        } catch StudioRefreshProcessError.outputTooLarge {
            return failure("The provider response was too large.")
        } catch {
            return failure("Studio could not read credentials or complete the provider check. Open Accounts for connection details.")
        }
    }
    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
