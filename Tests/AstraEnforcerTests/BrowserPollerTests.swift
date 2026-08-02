import AstraCore
import Foundation
import XCTest
@testable import AstraEnforcer

final class BrowserPollerTests: XCTestCase {
    func testRedirectsBlockedForegroundBrowserTab() {
        let foreground = FakeForegroundApplication(bundleIdentifier: SupportedBrowser.dia.bundleIdentifier)
        let dia = FakeBrowserAdapter(browser: .dia, activeURL: URL(string: "https://social.example.com/feed"))
        let poller = BrowserPoller(
            foregroundProvider: foreground,
            adapters: [.dia: dia],
            interval: 60
        )
        let blockPage = URL(string: "http://127.0.0.1:43123/blocked")!

        poller.start(domainRules: [try! DomainRule("example.com")], blockPageURL: blockPage)
        poller.pollOnce()
        poller.stop()

        XCTAssertEqual(dia.navigations, [blockPage])
    }

    func testDoesNotInspectBackgroundBrowser() {
        let foreground = FakeForegroundApplication(bundleIdentifier: "com.apple.finder")
        let safari = FakeBrowserAdapter(browser: .safari, activeURL: URL(string: "https://example.com"))
        let poller = BrowserPoller(foregroundProvider: foreground, adapters: [.safari: safari], interval: 60)

        poller.start(domainRules: [try! DomainRule("example.com")], blockPageURL: URL(string: "http://127.0.0.1:1/blocked")!)
        poller.pollOnce()
        poller.stop()

        XCTAssertEqual(safari.activeURLReadCount, 0)
        XCTAssertTrue(safari.navigations.isEmpty)
    }

    func testReportsAutomationDenial() {
        let foreground = FakeForegroundApplication(bundleIdentifier: SupportedBrowser.chrome.bundleIdentifier)
        let chrome = FakeBrowserAdapter(browser: .chrome, error: .permissionDenied(message: "Not authorized"))
        let delegate = RecordingBrowserPollerDelegate()
        let poller = BrowserPoller(foregroundProvider: foreground, adapters: [.chrome: chrome], interval: 60)
        poller.delegate = delegate

        poller.start(domainRules: [try! DomainRule("example.com")], blockPageURL: URL(string: "http://127.0.0.1:1/blocked")!)
        poller.pollOnce()
        poller.stop()

        XCTAssertEqual(delegate.lastHealth?.browser, .chrome)
        XCTAssertEqual(delegate.lastHealth?.permissionState, .denied)
        XCTAssertEqual(delegate.lastHealth?.message, "Not authorized")
    }
}

private final class FakeForegroundApplication: ForegroundApplicationProviding, @unchecked Sendable {
    var bundleIdentifier: String?
    init(bundleIdentifier: String?) { self.bundleIdentifier = bundleIdentifier }
    var frontmostBundleIdentifier: String? { bundleIdentifier }
}

private final class FakeBrowserAdapter: BrowserAutomating, @unchecked Sendable {
    let browser: SupportedBrowser
    private let url: URL?
    private let error: BrowserAutomationError?
    private let lock = NSLock()
    private(set) var activeURLReadCount = 0
    private(set) var navigations: [URL] = []

    init(browser: SupportedBrowser, activeURL: URL? = nil, error: BrowserAutomationError? = nil) {
        self.browser = browser
        self.url = activeURL
        self.error = error
    }

    func activeURL() throws -> URL? {
        lock.lock(); activeURLReadCount += 1; lock.unlock()
        if let error { throw error }
        return url
    }

    func navigateActiveTab(to url: URL) throws {
        lock.lock(); navigations.append(url); lock.unlock()
        if let error { throw error }
    }
}

private final class RecordingBrowserPollerDelegate: BrowserPollingDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var lastHealth: BrowserEnforcementHealth?

    func browserPoller(_ poller: BrowserPoller, didUpdate health: BrowserEnforcementHealth) {
        lock.lock(); lastHealth = health; lock.unlock()
    }
}
