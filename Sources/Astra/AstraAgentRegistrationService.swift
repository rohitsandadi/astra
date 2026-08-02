import AppKit
import ServiceManagement
import SwiftUI

enum AstraAgentRegistrationStatus: String, Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case requiresInstall
    case unavailable

    var title: String {
        switch self {
        case .enabled: "Enabled"
        case .notRegistered: "Not enabled"
        case .requiresApproval: "Approval required"
        case .requiresInstall: "Move to Applications"
        case .unavailable: "Unavailable in this build"
        }
    }

    var detail: String {
        switch self {
        case .enabled:
            "Astra can keep a focus session active when the main window is closed."
        case .notRegistered:
            "Enable the background helper before starting enforced sessions."
        case .requiresApproval:
            "Allow Astra in System Settings under General → Login Items & Extensions."
        case .requiresInstall:
            "Move Astra.app to Applications and reopen it before enabling Protection."
        case .unavailable:
            "Astra could not find its bundled background helper. Reinstall the app before starting enforced sessions."
        }
    }
}

@MainActor
final class AstraAgentRegistrationService: ObservableObject {
    static let shared = AstraAgentRegistrationService()
    private static let registrationVersionKey = "astra.helper-registration-build.v1"

    private static var currentRegistrationVersion: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "macos-helper-layout-2-build-\(build)"
    }

    @Published private(set) var status: AstraAgentRegistrationStatus = .notRegistered
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false

    private let service = SMAppService.agent(plistName: "com.rohitsandadi.astra.enforcer.plist")

    private init() {
        refresh()
    }

    func refresh() {
        status = Self.resolveStatus(
            serviceStatus: service.status,
            bundleURL: Bundle.main.bundleURL
        )
    }

    static func resolveStatus(
        serviceStatus: SMAppService.Status,
        bundleURL: URL,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> AstraAgentRegistrationStatus {
        switch serviceStatus {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            let helperPlist = bundleURL
                .appendingPathComponent("Contents/Library/LaunchAgents/com.rohitsandadi.astra.enforcer.plist")
            let isPackagedApp = bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
                && fileExists(helperPlist.path)
            guard isPackagedApp else { return .unavailable }

            let resolvedPath = bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
            let applicationsPath = URL(fileURLWithPath: "/Applications", isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            return resolvedPath.hasPrefix(applicationsPath + "/") ? .notRegistered : .requiresInstall
        case .notFound:
            return .unavailable
        @unknown default:
            return .notRegistered
        }
    }

    func register() {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try service.register()
            UserDefaults.standard.set(
                Self.currentRegistrationVersion,
                forKey: Self.registrationVersionKey
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    /// Apple requires re-registration after the helper plist or executable
    /// changes. Ad-hoc GitHub builds do not have a stable signing identity, so
    /// an outdated registration is removed and the user explicitly enables the
    /// newly downloaded build from Astra's truthful setup UI.
    func invalidateOutdatedRegistrationIfNeeded() async {
        refresh()
        guard status == .enabled,
              UserDefaults.standard.string(forKey: Self.registrationVersionKey)
                != Self.currentRegistrationVersion
        else { return }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await service.unregister()
            UserDefaults.standard.removeObject(forKey: Self.registrationVersionKey)
            errorMessage = "Astra was updated. Enable Protection again for this build."
        } catch {
            errorMessage = "Protection could not be updated: \(error.localizedDescription)"
        }
        refresh()
    }

    func unregister() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await service.unregister()
            UserDefaults.standard.removeObject(forKey: Self.registrationVersionKey)
        } catch {
            errorMessage = "Protection could not be disabled: \(error.localizedDescription)"
        }
        refresh()
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }
}
