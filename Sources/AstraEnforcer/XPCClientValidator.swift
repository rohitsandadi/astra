import Darwin
import Foundation

/// Restricts the per-user Mach service to the Astra executable shipped beside
/// this helper. Path validation works for ad-hoc-signed community builds, which
/// intentionally have no Apple Developer Team identifier to validate.
struct AstraXPCClientValidator {
    private let expectedExecutableURL: URL?

    init(helperExecutablePath: String? = nil) {
        let resolvedPath = helperExecutablePath ?? Self.currentExecutablePath()
        expectedExecutableURL = Self.expectedMainExecutable(
            forHelperAt: URL(fileURLWithPath: resolvedPath)
        )
    }

    func accepts(processIdentifier: pid_t) -> Bool {
        guard processIdentifier > 0,
              let expectedExecutableURL,
              let actualExecutableURL = Self.executableURL(for: processIdentifier)
        else {
            return false
        }
        return Self.canonical(actualExecutableURL) == Self.canonical(expectedExecutableURL)
    }

    static func expectedMainExecutable(forHelperAt helperURL: URL) -> URL? {
        let helper = canonical(helperURL)
        guard helper.lastPathComponent == "AstraEnforcer",
              helper.deletingLastPathComponent().lastPathComponent == "MacOS",
              helper.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Contents"
        else {
            return nil
        }

        return helper
            .deletingLastPathComponent()
            .appendingPathComponent("Astra", isDirectory: false)
    }

    private static func executableURL(for processIdentifier: pid_t) -> URL? {
        // PROC_PIDPATHINFO_MAXSIZE is a C macro Swift cannot import directly.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(processIdentifier, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
    }

    private static func currentExecutablePath() -> String {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return CommandLine.arguments[0]
        }
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
