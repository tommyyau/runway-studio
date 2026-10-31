import Foundation
import Darwin

@main
struct RunwayStudioTools {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        do { try await run(args) }
        catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(2)
        }
    }
    static func run(_ args: [String]) async throws {
        guard let command = args.first else { throw ToolError.usage }
        if command == "--help" || command == "help" { print(usage); return }
        let reader = StudioReader()
        if command == "mcp" {
            guard args.count == 1 else { throw ToolError.usage }
            var server = MCPServer()
            while let line = readLine() {
                let data = Data(line.utf8)
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let report = object?["method"] as? String == "tools/call" && object?["id"] != nil
                    ? await reader.read()
                    : Report(connected: false, source: "unavailable", observedAt: stamp(Date()), cards: [], message: nil)
                if let response = server.handle(data, report: report) {
                    FileHandle.standardOutput.write(response + Data([10]))
                }
            }
            return
        }
        if command == "statusline" {
            guard args.count == 1 || (args.count == 2 && args[1] == "--json") else { throw ToolError.usage }
            let report = await reader.read()
            if args.count == 2 {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                print(String(decoding: try encoder.encode(report), as: UTF8.self))
            } else if report.cards.isEmpty {
                print("Runway: unavailable")
            } else {
                print(report.cards.map { card in
                    let meters = card.meters.filter { ["Session", "Weekly"].contains($0.label) }.map { meter in
                        meter.remainingPercent.map { "\(meter.label) \(Int($0.rounded()))%" + (meter.source == "cache" ? " (cached)" : "") + ((meter.resetsAt.flatMap(parseDate).map { $0 <= Date() } ?? false) ? " (reset elapsed)" : "") } ?? "\(meter.label) unknown"
                    }.joined(separator: ", ")
                    return "\(card.displayName): \(meters.isEmpty ? "limits unavailable" : meters)\(card.stale ? " (cached/stale)" : "")"
                }.joined(separator: " | "))
            }
            return
        }
        if command == "wait" {
            guard args.count >= 2 else { throw ToolError.usage }
            let provider = args[1]
            guard !provider.isEmpty, !provider.hasPrefix("--") else { throw ToolError.usage }
            var metric = "Session", timeout = 300.0, poll = 15.0
            var i = 2
            while i < args.count {
                guard i + 1 < args.count else { throw ToolError.usage }
                switch args[i] {
                case "--metric": metric = args[i + 1]
                case "--timeout": guard let value = Double(args[i + 1]), value.isFinite, value > 0, value <= 86400 else { throw ToolError.usage }; timeout = value
                case "--poll": guard let value = Double(args[i + 1]), value.isFinite, value >= 1, value <= 3600 else { throw ToolError.usage }; poll = value
                default: throw ToolError.usage
                }
                i += 2
            }
            guard !metric.isEmpty else { throw ToolError.usage }
            let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(timeout))
            repeat {
                let report = await reader.read()
                if clock.now <= deadline && allowanceAvailable(report, provider: provider, metric: metric, now: Date()) {
                    print("\(provider) \(metric): allowance available")
                    return
                }
                let remaining = clock.now.duration(to: deadline)
                if remaining <= .zero { break }
                try await clock.sleep(for: min(.seconds(poll), remaining))
            } while clock.now < deadline
            FileHandle.standardError.write(Data("Timed out waiting for fresh \(provider) \(metric) allowance.\n".utf8))
            exit(1)
        }
        throw ToolError.usage
    }
    static let usage = """
    Usage: runway-studio statusline [--json]
           runway-studio wait <provider-or-card-id> [--metric Session] [--timeout seconds] [--poll seconds]
           runway-studio mcp
    """
    enum ToolError: LocalizedError {
        case usage
        var errorDescription: String? { RunwayStudioTools.usage }
    }
}
