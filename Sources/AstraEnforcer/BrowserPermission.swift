@preconcurrency import AppKit
import AstraCore
import CoreServices
import Foundation

protocol BrowserPermissionRequesting: Sendable {
    func permissionState(for browser: SupportedBrowser, askUserIfNeeded: Bool) -> BrowserEnforcementHealth
}

protocol BrowserApplicationProviding: Sendable {
    func applicationURL(for browser: SupportedBrowser) -> URL?
    func isRunning(_ browser: SupportedBrowser) -> Bool
    func launchWithoutActivation(at url: URL, timeout: TimeInterval) -> Result<Void, Error>
}

struct SystemBrowserApplicationProvider: BrowserApplicationProviding {
    func applicationURL(for browser: SupportedBrowser) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier)
    }

    func isRunning(_ browser: SupportedBrowser) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleIdentifier).isEmpty
    }

    func launchWithoutActivation(at url: URL, timeout: TimeInterval) -> Result<Void, Error> {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false

        let result = BrowserLaunchResult()
        let completed = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            result.set(error.map(Result.failure) ?? .success(()))
            completed.signal()
        }
        guard completed.wait(timeout: .now() + timeout) == .success else {
            return .failure(BrowserPermissionError.launchTimedOut)
        }
        return result.get() ?? .failure(BrowserPermissionError.launchFailed("The browser did not report a launch result."))
    }
}

protocol AppleEventPermissionDetermining: Sendable {
    func determinePermission(bundleIdentifier: String, askUserIfNeeded: Bool) -> OSStatus
}

struct SystemAppleEventPermissionDeterminer: AppleEventPermissionDetermining {
    func determinePermission(bundleIdentifier: String, askUserIfNeeded: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let identifierData = Data(bundleIdentifier.utf8)
        let createStatus = identifierData.withUnsafeBytes { bytes in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                bytes.baseAddress,
                bytes.count,
                &target
            )
        }
        guard createStatus == noErr else { return OSStatus(createStatus) }
        defer { AEDisposeDesc(&target) }

        return AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )
    }
}

enum BrowserPermissionError: LocalizedError, Equatable, Sendable {
    case launchTimedOut
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchTimedOut:
            "The browser took too long to open. Open it manually, then try again."
        case .launchFailed(let message):
            "The browser could not be opened: \(message)"
        }
    }
}

/// Queries TCC without sending browser navigation events. On an explicit user
/// request, a closed browser is opened without activation because Apple's TCC
/// API requires the target process to already be running before it can prompt.
struct AppleEventBrowserPermissionRequester: BrowserPermissionRequesting {
    private let applications: BrowserApplicationProviding
    private let permissionDeterminer: AppleEventPermissionDetermining
    private let launchTimeout: TimeInterval

    init(
        applications: BrowserApplicationProviding = SystemBrowserApplicationProvider(),
        permissionDeterminer: AppleEventPermissionDetermining = SystemAppleEventPermissionDeterminer(),
        launchTimeout: TimeInterval = 8
    ) {
        self.applications = applications
        self.permissionDeterminer = permissionDeterminer
        self.launchTimeout = launchTimeout
    }

    func permissionState(for browser: SupportedBrowser, askUserIfNeeded: Bool) -> BrowserEnforcementHealth {
        guard let applicationURL = applications.applicationURL(for: browser) else {
            return health(
                browser,
                installed: false,
                state: .unavailable,
                message: "\(browser.displayName) is not installed."
            )
        }

        if !applications.isRunning(browser) {
            guard askUserIfNeeded else {
                return health(browser, state: .notDetermined)
            }
            switch applications.launchWithoutActivation(at: applicationURL, timeout: launchTimeout) {
            case .success:
                break
            case .failure(let error):
                return health(browser, state: .incompatible, message: error.localizedDescription)
            }
        }

        let status = permissionDeterminer.determinePermission(
            bundleIdentifier: browser.bundleIdentifier,
            askUserIfNeeded: askUserIfNeeded
        )
        switch status {
        case noErr:
            return health(browser, state: .authorized)
        case OSStatus(errAEEventNotPermitted):
            return health(
                browser,
                state: .denied,
                message: "Allow Astra to control \(browser.displayName) in System Settings → Privacy & Security → Automation."
            )
        case OSStatus(errAEEventWouldRequireUserConsent):
            return health(
                browser,
                state: .notDetermined,
                message: "Automation permission has not been requested yet."
            )
        case OSStatus(procNotFound):
            return health(
                browser,
                state: .notDetermined,
                message: "Open \(browser.displayName), then request Automation permission again."
            )
        default:
            return health(
                browser,
                state: .incompatible,
                message: "Automation permission check failed (error \(status))."
            )
        }
    }

    private func health(
        _ browser: SupportedBrowser,
        installed: Bool = true,
        state: BrowserPermissionState,
        message: String? = nil
    ) -> BrowserEnforcementHealth {
        BrowserEnforcementHealth(
            browser: browser,
            isInstalled: installed,
            permissionState: state,
            message: message
        )
    }
}

private final class BrowserLaunchResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?

    func set(_ result: Result<Void, Error>) {
        lock.withLock { self.result = result }
    }

    func get() -> Result<Void, Error>? {
        lock.withLock { result }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
