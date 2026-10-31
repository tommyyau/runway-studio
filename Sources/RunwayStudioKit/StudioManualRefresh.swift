import Darwin
import Foundation
import OSLog

struct StudioManualRefreshResult: Sendable {
    let providerID: String
    /// Timestamp reported by the tracker, not the time the helper was launched.
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
    case helperUnavailable, timedOut, outputTooLarge, cancelled, launchFailed
}

/// Invoked by Studio’s single polling coordinator for automatic and manual refreshes. A bare family token refreshes all its cards;
/// the caller must deduplicate requests and enforce waits across that family. The runner is injectable.
struct StudioManualRefreshClient: Sendable {
    typealias Runner = @Sendable (_ arguments: [String], _ timeout: TimeInterval) async throws -> StudioRefreshProcessOutput
    let runner: Runner
    init(runner: @escaping Runner = StudioRefreshProcessRunner.run) { self.runner = runner }

    static func cancelOutstanding() { StudioActiveRefreshes.shared.cancelAll() }

    func refresh(providerID: String) async -> StudioManualRefreshResult {
        func failure(_ message: String) -> StudioManualRefreshResult {
            Logger(subsystem: "local.runway.studio", category: "manual-refresh").error("\(providerID, privacy: .public): \(message, privacy: .public)")
            return StudioManualRefreshResult(providerID: providerID, fetchedAt: nil, fetchedAtByProvider: [:], failedProviderIDs: [], warning: nil, error: message)
        }
        let family = providerID.split(separator: "@", maxSplits: 1).first.map(String.init)
        guard ["claude", "codex"].contains(family ?? ""),
              !providerID.hasPrefix("-"), !providerID.hasSuffix("@") else {
            return failure("This card cannot be refreshed individually with the installed Runway helper.")
        }
        do {
            let result = try await runner([providerID, "--force"], 45)
            guard result.stdout.count <= StudioRefreshProcessRunner.outputLimit,
                  result.stderr.count <= StudioRefreshProcessRunner.outputLimit else { throw StudioRefreshProcessError.outputTooLarge }
            guard result.status == 0 || result.status == 4 else {
                return failure("Runway could not refresh this card (helper exit \(result.status)).")
            }
            guard let object = try JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
                  object["schema"] as? String == "runway.limits.v1",
                  let providers = object["providers"] as? [String: [String: Any]],
                  let errors = object["errors"] as? [[String: Any]] else {
                return failure("Runway returned an invalid refresh response.")
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
                return failure("Runway returned no usable reading for this selection. Check Runway for details.")
            }
            return StudioManualRefreshResult(providerID: providerID, fetchedAt: dates[providerID],
                fetchedAtByProvider: dates, failedProviderIDs: failed,
                warning: result.status == 4 || !errors.isEmpty ? "Runway reported a partial refresh; check Runway for details." : nil,
                error: nil, limitsData: result.stdout)
        } catch StudioRefreshProcessError.helperUnavailable {
            return failure("Runway's signed refresh helper is unavailable. Install Runway in Applications and try again.")
        } catch StudioRefreshProcessError.timedOut {
            return failure("Runway's refresh timed out after 45 seconds.")
        } catch StudioRefreshProcessError.cancelled {
            return failure("Refresh cancelled.")
        } catch StudioRefreshProcessError.outputTooLarge {
            return failure("Runway's refresh response was too large.")
        } catch {
            return failure("Runway's refresh helper could not be run or returned an invalid response.")
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

private enum StudioRefreshProcessRunner {
    static let outputLimit = 512 * 1024
    static let helper = URL(fileURLWithPath: "/Applications/Runway.app/Contents/Helpers/runway")

    static func run(_ arguments: [String], timeout: TimeInterval) async throws -> StudioRefreshProcessOutput {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw StudioRefreshProcessError.helperUnavailable }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("runway-studio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let stdout = root.appendingPathComponent("stdout"), stderr = root.appendingPathComponent("stderr")
        guard FileManager.default.createFile(atPath: stdout.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              FileManager.default.createFile(atPath: stderr.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw StudioRefreshProcessError.launchFailed
        }
        let outputFile = try FileHandle(forWritingTo: stdout), errorFile = try FileHandle(forWritingTo: stderr)
        defer { try? outputFile.close(); try? errorFile.close() }
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        process.standardOutput = outputFile
        process.standardError = errorFile
        do { try process.run() } catch { throw StudioRefreshProcessError.launchFailed }
        StudioActiveRefreshes.shared.add(process)
        defer { StudioActiveRefreshes.shared.remove(process) }
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(timeout))
        while process.isRunning {
            for url in [stdout, stderr] {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                if size > outputLimit { kill(process.processIdentifier, SIGKILL); throw StudioRefreshProcessError.outputTooLarge }
            }
            if Task.isCancelled || clock.now >= deadline {
                kill(process.processIdentifier, SIGKILL)
                throw Task.isCancelled ? StudioRefreshProcessError.cancelled : StudioRefreshProcessError.timedOut
            }
            do { try await clock.sleep(for: .milliseconds(100)) }
            catch { kill(process.processIdentifier, SIGKILL); throw StudioRefreshProcessError.cancelled }
        }
        func read(_ url: URL) throws -> Data {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: outputLimit + 1) ?? Data()
            guard data.count <= outputLimit else { throw StudioRefreshProcessError.outputTooLarge }
            return data
        }
        return StudioRefreshProcessOutput(status: process.terminationStatus, stdout: try read(stdout), stderr: try read(stderr))
    }
}

/// Synchronous shutdown: NSApplication termination does not wait for task cancellation to unwind.
final class StudioActiveRefreshes: @unchecked Sendable {
    static let shared = StudioActiveRefreshes()
    private let lock = NSLock()
    private var processes: [Int32: Process] = [:]
    func add(_ process: Process) { lock.withLock { processes[process.processIdentifier] = process } }
    func remove(_ process: Process) { _ = lock.withLock { processes.removeValue(forKey: process.processIdentifier) } }
    func cancelAll() {
        let active = lock.withLock { Array(processes.values) }
        for process in active where process.isRunning { kill(process.processIdentifier, SIGTERM) }
    }
}
