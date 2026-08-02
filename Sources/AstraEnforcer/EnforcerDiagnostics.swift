@preconcurrency import AppKit
import AstraCore
import Foundation

struct EnforcerDiagnosticReport: Codable, Equatable, Sendable {
    struct Browser: Codable, Equatable, Sendable {
        let name: String
        let bundleIdentifier: String
        let installed: Bool
        let running: Bool
    }

    let executablePath: String
    let bundleIdentifier: String?
    let hasAppleEventsUsageDescription: Bool
    let expectedMainExecutablePath: String?
    let browsers: [Browser]
}

enum EnforcerDiagnostics {
    static func report() -> EnforcerDiagnosticReport {
        let executablePath = currentExecutablePath()
        return EnforcerDiagnosticReport(
            executablePath: executablePath,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            hasAppleEventsUsageDescription: !(Bundle.main.object(
                forInfoDictionaryKey: "NSAppleEventsUsageDescription"
            ) as? String ?? "").isEmpty,
            expectedMainExecutablePath: AstraXPCClientValidator.expectedMainExecutable(
                forHelperAt: URL(fileURLWithPath: executablePath)
            )?.path,
            browsers: SupportedBrowser.allCases.map { browser in
                EnforcerDiagnosticReport.Browser(
                    name: browser.displayName,
                    bundleIdentifier: browser.bundleIdentifier,
                    installed: NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: browser.bundleIdentifier
                    ) != nil,
                    running: !NSRunningApplication.runningApplications(
                        withBundleIdentifier: browser.bundleIdentifier
                    ).isEmpty
                )
            }
        )
    }

    static func encodedReport() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report())
    }

    private static func currentExecutablePath() -> String {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return CommandLine.arguments[0]
        }
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
