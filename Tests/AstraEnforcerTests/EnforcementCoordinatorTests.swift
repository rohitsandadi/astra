import AstraCore
import Foundation
import XCTest
@testable import AstraEnforcer

final class EnforcementCoordinatorTests: XCTestCase {
    func testLockedSessionRejectsInterruptionInsideHelperOwner() throws {
        let harness = Harness(difficulty: .locked)
        _ = try harness.coordinator.start(harness.startRequest)

        XCTAssertThrowsError(
            try harness.coordinator.requestInterruption(AstraInterruptionRequest(kind: .endSession))
        ) { error in
            XCTAssertEqual(error as? FocusSessionEngineError, .interruptionNotAllowed)
        }
    }

    func testCancellingCommitmentChallengeRetainsEscalation() throws {
        let harness = Harness(difficulty: .commitment)
        _ = try harness.coordinator.start(harness.startRequest)
        let first = try harness.coordinator.requestInterruption(AstraInterruptionRequest(kind: .endSession))
        XCTAssertEqual(first.challenge.availableAt.timeIntervalSince(first.challenge.requestedAt), 30)

        _ = try harness.coordinator.cancelInterruption(
            AstraCancelInterruptionRequest(challengeID: first.challenge.id)
        )
        let second = try harness.coordinator.requestInterruption(AstraInterruptionRequest(kind: .endSession))

        XCTAssertEqual(second.challenge.availableAt.timeIntervalSince(second.challenge.requestedAt), 60)
        XCTAssertEqual(second.snapshot.session?.interruptionRequestCount, 2)
    }

    func testBreakPausesAndThenRestoresEnforcementWithoutExtendingSession() throws {
        let harness = Harness(difficulty: .flexible)
        let started = try harness.coordinator.start(harness.startRequest)
        let originalEnd = try XCTUnwrap(started.session?.endDate)
        let requested = try harness.coordinator.requestInterruption(
            AstraInterruptionRequest(kind: .takeBreak, breakDurationMinutes: 1)
        )

        harness.clock.advance(by: 6)
        let onBreak = try harness.coordinator.commitInterruption(
            AstraCommitInterruptionRequest(challengeID: requested.challenge.id)
        )
        XCTAssertEqual(onBreak.session?.status, .onBreak)
        XCTAssertEqual(harness.pageServer.stopCount, 1)

        harness.clock.advance(by: 60)
        let resumed = harness.coordinator.currentSnapshot()
        XCTAssertEqual(resumed.session?.status, .active)
        XCTAssertEqual(resumed.session?.endDate, originalEnd)
        XCTAssertEqual(harness.pageServer.startCount, 2)
    }

    func testExpiredPersistedSessionIsClearedWithoutStartingEnforcement() throws {
        let harness = Harness(difficulty: .flexible)
        let oldPreset = harness.preset
        harness.store.session = FocusSession(
            preset: oldPreset,
            startDate: harness.clock.date.addingTimeInterval(-600),
            endDate: harness.clock.date.addingTimeInterval(-300),
            difficulty: .flexible
        )

        try harness.coordinator.restore()

        XCTAssertNil(harness.coordinator.currentSnapshot().session)
        XCTAssertNil(harness.store.session)
        XCTAssertEqual(harness.pageServer.startCount, 0)
    }

    func testWakeReconciliationEndsSessionAtWallClockDeadline() throws {
        let harness = Harness(difficulty: .locked)
        _ = try harness.coordinator.start(harness.startRequest)

        harness.clock.advance(by: 601)
        harness.coordinator.reconcileAfterWake()

        XCTAssertEqual(harness.coordinator.currentSnapshot().session?.status, .completed)
        XCTAssertNil(harness.store.session)
        XCTAssertEqual(harness.pageServer.stopCount, 1)
    }
}

private final class Harness {
    let clock = LockedClock(Date(timeIntervalSince1970: 10_000))
    let store = MemorySessionStore()
    let pageServer = FakeBlockPageServer()
    let workspace = CoordinatorFakeWorkspace()
    let coordinator: EnforcementCoordinator
    let preset: FocusPreset

    init(difficulty: Difficulty) {
        preset = FocusPreset(
            name: "Deep work",
            blockedApplications: [],
            domainRules: [try! DomainRule("example.com")],
            defaultDurationSeconds: 600,
            difficulty: difficulty,
            createdAt: clock.date,
            updatedAt: clock.date
        )
        let blocker = ApplicationBlocker(
            workspace: workspace,
            scheduler: CoordinatorImmediateTerminationScheduler()
        )
        let poller = BrowserPoller(
            foregroundProvider: NoForegroundApplication(),
            adapters: [:],
            interval: 3_600
        )
        coordinator = EnforcementCoordinator(
            applicationBlocker: blocker,
            browserPoller: poller,
            blockPageServer: pageServer,
            sessionStore: store,
            completionScheduler: RecordingCompletionScheduler(),
            installationProvider: AllInstalledProvider(),
            permissionRequester: AuthorizedPermissionRequester(),
            now: { [clock] in clock.date }
        )
    }

    var startRequest: AstraStartSessionRequest {
        AstraStartSessionRequest(preset: preset, durationSeconds: 600, intention: "Finish the draft")
    }
}

private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var date: Date { lock.withLock { value } }
    func advance(by interval: TimeInterval) { lock.withLock { value = value.addingTimeInterval(interval) } }
}

private final class MemorySessionStore: SessionPersisting, @unchecked Sendable {
    private let lock = NSLock()
    var session: FocusSession? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
    private var value: FocusSession?
    func load() throws -> FocusSession? { session }
    func save(_ session: FocusSession) throws { self.session = session }
    func clear() throws { session = nil }
}

private final class FakeBlockPageServer: BlockPageServing, @unchecked Sendable {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start(for session: FocusSession) throws -> URL {
        startCount += 1
        return URL(string: "http://127.0.0.1:43210/blocked")!
    }
    func stop() { stopCount += 1 }
}

private final class CoordinatorFakeWorkspace: WorkspaceApplicationProviding, @unchecked Sendable {
    var runningApplications: [any RunningApplicationControlling] = []
    private var launchHandler: (@Sendable (any RunningApplicationControlling) -> Void)?
    func observeLaunches(_ handler: @escaping @Sendable (any RunningApplicationControlling) -> Void) -> NSObjectProtocol {
        launchHandler = handler
        return NSObject()
    }
    func removeObserver(_ token: NSObjectProtocol) { launchHandler = nil }
}

private struct CoordinatorImmediateTerminationScheduler: TerminationScheduling {
    func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void) { action() }
}

private struct NoForegroundApplication: ForegroundApplicationProviding {
    var frontmostBundleIdentifier: String? { nil }
}

private final class RecordingCompletion: CancellableSchedule, @unchecked Sendable {
    func cancel() {}
}

private struct RecordingCompletionScheduler: SessionCompletingScheduling {
    func schedule(at date: Date, _ action: @escaping @Sendable () -> Void) -> any CancellableSchedule {
        RecordingCompletion()
    }
}

private struct AllInstalledProvider: ApplicationInstallationProviding {
    func isInstalled(bundleIdentifier: String) -> Bool { true }
}

private struct AuthorizedPermissionRequester: BrowserPermissionRequesting {
    func permissionState(for browser: SupportedBrowser, askUserIfNeeded: Bool) -> BrowserEnforcementHealth {
        BrowserEnforcementHealth(browser: browser, isInstalled: true, permissionState: .authorized)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
