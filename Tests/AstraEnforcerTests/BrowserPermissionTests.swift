import AstraCore
import CoreServices
import Foundation
import XCTest
@testable import AstraEnforcer

final class BrowserPermissionTests: XCTestCase {
    func testReportsBrowserAsUnavailableWhenItIsNotInstalled() {
        let applications = FakeBrowserApplications(installed: false, running: false)
        let determiner = FakePermissionDeterminer(status: noErr)
        let requester = AppleEventBrowserPermissionRequester(
            applications: applications,
            permissionDeterminer: determiner
        )

        let health = requester.permissionState(for: .dia, askUserIfNeeded: true)

        XCTAssertFalse(health.isInstalled)
        XCTAssertEqual(health.permissionState, .unavailable)
        XCTAssertEqual(applications.launchCount, 0)
        XCTAssertEqual(determiner.callCount, 0)
    }

    func testReadOnlyHealthCheckDoesNotLaunchClosedBrowserOrPrompt() {
        let applications = FakeBrowserApplications(installed: true, running: false)
        let determiner = FakePermissionDeterminer(status: noErr)
        let requester = AppleEventBrowserPermissionRequester(
            applications: applications,
            permissionDeterminer: determiner
        )

        let health = requester.permissionState(for: .dia, askUserIfNeeded: false)

        XCTAssertEqual(health.permissionState, .notDetermined)
        XCTAssertEqual(applications.launchCount, 0)
        XCTAssertEqual(determiner.callCount, 0)
    }

    func testExplicitRequestLaunchesClosedBrowserThenPrompts() {
        let applications = FakeBrowserApplications(installed: true, running: false)
        let determiner = FakePermissionDeterminer(status: noErr)
        let requester = AppleEventBrowserPermissionRequester(
            applications: applications,
            permissionDeterminer: determiner
        )

        let health = requester.permissionState(for: .dia, askUserIfNeeded: true)

        XCTAssertEqual(health.permissionState, .authorized)
        XCTAssertEqual(applications.launchCount, 1)
        XCTAssertEqual(determiner.callCount, 1)
        XCTAssertEqual(determiner.lastAskUserIfNeeded, true)
        XCTAssertEqual(determiner.lastBundleIdentifier, SupportedBrowser.dia.bundleIdentifier)
    }

    func testDeniedPermissionHasActionableSystemSettingsMessage() {
        let requester = AppleEventBrowserPermissionRequester(
            applications: FakeBrowserApplications(installed: true, running: true),
            permissionDeterminer: FakePermissionDeterminer(status: OSStatus(errAEEventNotPermitted))
        )

        let health = requester.permissionState(for: .safari, askUserIfNeeded: true)

        XCTAssertEqual(health.permissionState, .denied)
        XCTAssertTrue(health.message?.contains("Privacy & Security → Automation") == true)
    }

    func testLaunchFailureDoesNotAttemptPermissionPrompt() {
        let applications = FakeBrowserApplications(
            installed: true,
            running: false,
            launchResult: .failure(BrowserPermissionError.launchTimedOut)
        )
        let determiner = FakePermissionDeterminer(status: noErr)
        let requester = AppleEventBrowserPermissionRequester(
            applications: applications,
            permissionDeterminer: determiner
        )

        let health = requester.permissionState(for: .chrome, askUserIfNeeded: true)

        XCTAssertEqual(health.permissionState, .incompatible)
        XCTAssertTrue(health.message?.contains("too long") == true)
        XCTAssertEqual(determiner.callCount, 0)
    }
}

private final class FakeBrowserApplications: BrowserApplicationProviding, @unchecked Sendable {
    private let installed: Bool
    private let running: Bool
    private let launchResult: Result<Void, Error>
    private(set) var launchCount = 0

    init(
        installed: Bool,
        running: Bool,
        launchResult: Result<Void, Error> = .success(())
    ) {
        self.installed = installed
        self.running = running
        self.launchResult = launchResult
    }

    func applicationURL(for browser: SupportedBrowser) -> URL? {
        installed ? URL(fileURLWithPath: "/Applications/\(browser.displayName).app") : nil
    }

    func isRunning(_ browser: SupportedBrowser) -> Bool { running }

    func launchWithoutActivation(at url: URL, timeout: TimeInterval) -> Result<Void, Error> {
        launchCount += 1
        return launchResult
    }
}

private final class FakePermissionDeterminer: AppleEventPermissionDetermining, @unchecked Sendable {
    private let status: OSStatus
    private(set) var callCount = 0
    private(set) var lastAskUserIfNeeded: Bool?
    private(set) var lastBundleIdentifier: String?

    init(status: OSStatus) { self.status = status }

    func determinePermission(bundleIdentifier: String, askUserIfNeeded: Bool) -> OSStatus {
        callCount += 1
        lastAskUserIfNeeded = askUserIfNeeded
        lastBundleIdentifier = bundleIdentifier
        return status
    }
}
