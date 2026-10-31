import Darwin
import Foundation

/// One alert evaluator per user, including launches outside LaunchServices. Preview exports skip
/// this lock because their notification coordinator is suppressed.
final class StudioProcessLock {
    private var descriptor: Int32 = -1
    private let directory: URL
    private let filename: String
    init(directory: URL? = nil, filename: String = "monitor.lock") {
        self.filename = filename
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RunwayStudio", isDirectory: true)
    }
    func acquire() throws -> Bool {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent(filename).path
        let file = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard file >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard flock(file, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno; Darwin.close(file)
            if code == EWOULDBLOCK { return false }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        descriptor = file
        return true
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
}
