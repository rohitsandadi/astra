import AppKit
import Foundation
import XCTest
@testable import AstraEnforcer

final class ApplicationBlockerTests: XCTestCase {
    func testTerminatesRunningBlockedAppAndForceTerminatesAfterGracePeriod() {
        let app = FakeRunningApplication(bundleIdentifier: "com.example.distraction", pid: 44)
        let workspace = FakeWorkspace(runningApplications: [app])
        let scheduler = ManualTerminationScheduler()
        let blocker = ApplicationBlocker(workspace: workspace, scheduler: scheduler, gracePeriod: 2)

        blocker.start(blocking: ["com.example.distraction"])
        XCTAssertEqual(app.terminateCount, 1)
        XCTAssertEqual(app.forceTerminateCount, 0)

        scheduler.runAll()
        XCTAssertEqual(app.forceTerminateCount, 1)
        blocker.stop()
    }

    func testDoesNotForceTerminateAfterGracefulExit() {
        let app = FakeRunningApplication(bundleIdentifier: "com.example.distraction", pid: 45)
        let workspace = FakeWorkspace(runningApplications: [app])
        let scheduler = ManualTerminationScheduler()
        let blocker = ApplicationBlocker(workspace: workspace, scheduler: scheduler)

        blocker.start(blocking: ["com.example.distraction"])
        app.terminated = true
        scheduler.runAll()

        XCTAssertEqual(app.terminateCount, 1)
        XCTAssertEqual(app.forceTerminateCount, 0)
        blocker.stop()
    }

    func testHandlesAppsLaunchedAfterSessionStarts() {
        let workspace = FakeWorkspace(runningApplications: [])
        let scheduler = ManualTerminationScheduler()
        let blocker = ApplicationBlocker(workspace: workspace, scheduler: scheduler)
        blocker.start(blocking: ["com.example.distraction"])

        let launched = FakeRunningApplication(bundleIdentifier: "com.example.distraction", pid: 46)
        workspace.emitLaunch(launched)

        XCTAssertEqual(launched.terminateCount, 1)
        blocker.stop()
    }

    func testNeverTerminatesProtectedSystemOrAstraProcesses() {
        for bundleIdentifier in ApplicationBlocker.protectedBundleIdentifiers {
            let app = FakeRunningApplication(bundleIdentifier: bundleIdentifier, pid: 47)
            let workspace = FakeWorkspace(runningApplications: [app])
            let blocker = ApplicationBlocker(workspace: workspace, scheduler: ManualTerminationScheduler())
            blocker.start(blocking: [bundleIdentifier])
            XCTAssertEqual(app.terminateCount, 0, bundleIdentifier)
            blocker.stop()
        }
    }

    func testLiveSystemWorkspaceTerminatesOptInProbe() throws {
        guard ProcessInfo.processInfo.environment["ASTRA_RUN_LIVE_APP_BLOCK_TEST"] == "1" else {
            throw XCTSkip("Set ASTRA_RUN_LIVE_APP_BLOCK_TEST=1 to run the disposable-app integration check.")
        }

        let bundleIdentifier = "com.rohitsandadi.astra.blockprobe"
        guard let probe = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            XCTFail("Launch the Astra Block Probe app before running this opt-in test.")
            return
        }

        let blocker = ApplicationBlocker()
        blocker.start(blocking: [bundleIdentifier])
        defer { blocker.stop() }

        let deadline = Date.now.addingTimeInterval(5)
        while !probe.isTerminated, Date.now < deadline {
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.05))
        }

        XCTAssertTrue(probe.isTerminated, "The real workspace blocker did not terminate the probe app.")
    }
}

private final class FakeRunningApplication: RunningApplicationControlling, @unchecked Sendable {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    var terminated = false
    private(set) var terminateCount = 0
    private(set) var forceTerminateCount = 0

    init(bundleIdentifier: String?, pid: pid_t) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = pid
    }

    var isTerminated: Bool { terminated }
    func terminate() -> Bool { terminateCount += 1; return true }
    func forceTerminate() -> Bool { forceTerminateCount += 1; terminated = true; return true }
}

private final class FakeWorkspace: WorkspaceApplicationProviding, @unchecked Sendable {
    var runningApplications: [any RunningApplicationControlling]
    private var launchHandler: (@Sendable (any RunningApplicationControlling) -> Void)?

    init(runningApplications: [any RunningApplicationControlling]) {
        self.runningApplications = runningApplications
    }

    func observeLaunches(_ handler: @escaping @Sendable (any RunningApplicationControlling) -> Void) -> NSObjectProtocol {
        launchHandler = handler
        return NSObject()
    }

    func removeObserver(_ token: NSObjectProtocol) {
        launchHandler = nil
    }

    func emitLaunch(_ application: any RunningApplicationControlling) {
        launchHandler?(application)
    }
}

private final class ManualTerminationScheduler: TerminationScheduling, @unchecked Sendable {
    private var actions: [@Sendable () -> Void] = []
    func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void) { actions.append(action) }
    func runAll() { let pending = actions; actions = []; pending.forEach { $0() } }
}
