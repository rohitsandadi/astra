@preconcurrency import AppKit
import AstraCore
import Foundation

enum BrowserAutomationError: Error, Equatable, Sendable {
    case consentRequired
    case permissionDenied(message: String)
    case scriptFailure(code: Int?, message: String)

    var permissionState: (BrowserPermissionState, String?) {
        switch self {
        case .consentRequired:
            (.notDetermined, "Automation consent has not been granted yet.")
        case .permissionDenied(let message):
            (.denied, message)
        case .scriptFailure(_, let message):
            (.incompatible, message)
        }
    }
}

protocol BrowserAutomating: Sendable {
    var browser: SupportedBrowser { get }
    func activeURL() throws -> URL?
    func navigateActiveTab(to url: URL) throws
}

/// Executes the small, bundled AppleScript snippets needed for browser tab access.
/// No script text is sourced from user data.
final class AppleScriptBrowserAdapter: BrowserAutomating, @unchecked Sendable {
    let browser: SupportedBrowser

    init(browser: SupportedBrowser) {
        self.browser = browser
    }

    func activeURL() throws -> URL? {
        let tabExpression = browser == .safari ? "current tab of front window" : "active tab of front window"
        let source = """
        tell application id "\(browser.bundleIdentifier)"
            if (count of windows) is 0 then return ""
            return URL of \(tabExpression)
        end tell
        """

        let value = try execute(source)
        guard let string = value.stringValue, !string.isEmpty else { return nil }
        return URL(string: string)
    }

    func navigateActiveTab(to url: URL) throws {
        let escapedURL = Self.appleScriptStringLiteral(url.absoluteString)
        let tabExpression = browser == .safari ? "current tab of front window" : "active tab of front window"
        let source = """
        tell application id "\(browser.bundleIdentifier)"
            if (count of windows) is 0 then return
            set URL of \(tabExpression) to \(escapedURL)
        end tell
        """
        _ = try execute(source)
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw BrowserAutomationError.scriptFailure(code: nil, message: "Unable to construct browser automation script.")
        }

        var details: NSDictionary?
        let result = script.executeAndReturnError(&details)
        guard details == nil else {
            let code = details?[NSAppleScript.errorNumber] as? Int
            let message = (details?[NSAppleScript.errorMessage] as? String)
                ?? (details?[NSAppleScript.errorBriefMessage] as? String)
                ?? "Browser automation failed."

            if code == -1743 {
                throw BrowserAutomationError.permissionDenied(message: message)
            }
            if code == -1744 {
                throw BrowserAutomationError.consentRequired
            }
            throw BrowserAutomationError.scriptFailure(code: code, message: message)
        }
        return result
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

protocol ForegroundApplicationProviding: Sendable {
    var frontmostBundleIdentifier: String? { get }
}

struct SystemForegroundApplicationProvider: ForegroundApplicationProviding {
    var frontmostBundleIdentifier: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

protocol BrowserPollingDelegate: AnyObject, Sendable {
    func browserPoller(_ poller: BrowserPoller, didUpdate health: BrowserEnforcementHealth)
}

/// Polls only the supported browser currently in the foreground. This avoids both
/// unnecessary Apple Events and unexpected changes to background browser windows.
final class BrowserPoller: @unchecked Sendable {
    weak var delegate: BrowserPollingDelegate?

    private let foregroundProvider: ForegroundApplicationProviding
    private let adapters: [SupportedBrowser: any BrowserAutomating]
    private let queue: DispatchQueue
    private let interval: TimeInterval
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var domainRules: [DomainRule] = []
    private var blockPageURL: URL?
    private var lastRedirectedSourceURL: URL?

    init(
        foregroundProvider: ForegroundApplicationProviding = SystemForegroundApplicationProvider(),
        adapters: [SupportedBrowser: any BrowserAutomating] = Dictionary(
            uniqueKeysWithValues: SupportedBrowser.allCases.map { ($0, AppleScriptBrowserAdapter(browser: $0)) }
        ),
        interval: TimeInterval = 0.5,
        queue: DispatchQueue = DispatchQueue(label: "com.rohitsandadi.astra.browser-poller", qos: .userInitiated)
    ) {
        self.foregroundProvider = foregroundProvider
        self.adapters = adapters
        self.interval = interval
        self.queue = queue
    }

    func start(domainRules: [DomainRule], blockPageURL: URL) {
        stop()
        lock.withLock {
            self.domainRules = domainRules
            self.blockPageURL = blockPageURL
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.pollOnce() }
        lock.withLock { self.timer = timer }
        timer.resume()
    }

    func stop() {
        let existing = lock.withLock { () -> DispatchSourceTimer? in
            defer { timer = nil }
            return timer
        }
        existing?.setEventHandler {}
        existing?.cancel()
    }

    func pollOnce() {
        guard let browser = SupportedBrowser.browser(forBundleIdentifier: foregroundProvider.frontmostBundleIdentifier),
              let adapter = adapters[browser] else {
            return
        }

        let state = lock.withLock { (domainRules, blockPageURL) }
        guard let blockPageURL = state.1 else { return }

        do {
            guard let currentURL = try adapter.activeURL() else {
                report(browser: browser, permission: .authorized)
                return
            }
            if state.0.contains(where: { $0.matches(url: currentURL) }),
               currentURL != blockPageURL,
               currentURL != lock.withLock({ lastRedirectedSourceURL }) {
                try adapter.navigateActiveTab(to: blockPageURL)
                lock.withLock { lastRedirectedSourceURL = currentURL }
                EnforcerLog.browsers.notice("Redirected a blocked tab in \(browser.displayName, privacy: .public)")
            } else {
                lock.withLock { lastRedirectedSourceURL = nil }
            }
            report(browser: browser, permission: .authorized)
        } catch let error as BrowserAutomationError {
            let state = error.permissionState
            EnforcerLog.browsers.error(
                "Automation failed in \(browser.displayName, privacy: .public): \((state.1 ?? String(describing: state.0)), privacy: .public)"
            )
            report(browser: browser, permission: state.0, message: state.1)
        } catch {
            report(browser: browser, permission: .incompatible, message: error.localizedDescription)
        }
    }

    private func report(browser: SupportedBrowser, permission: BrowserPermissionState, message: String? = nil) {
        delegate?.browserPoller(
            self,
            didUpdate: BrowserEnforcementHealth(
                browser: browser,
                isInstalled: true,
                permissionState: permission,
                message: message
            )
        )
    }

    deinit { stop() }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
