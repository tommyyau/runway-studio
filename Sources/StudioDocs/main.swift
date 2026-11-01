import AppKit
import RunwayStudioKit

@main struct StudioDocs {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("Usage: studio-docs OUTPUT_DIRECTORY\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                try await StudioDocumentationImages.export(to: URL(fileURLWithPath: CommandLine.arguments[1]))
                exit(0)
            } catch {
                fputs("Documentation rendering failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }
}
