@preconcurrency import AppKit
import AstraCore
import Foundation

protocol SessionCompletingScheduling: Sendable {
    func schedule(at date: Date, _ action: @escaping @Sendable () -> Void) -> any CancellableSchedule
}

protocol CancellableSchedule: AnyObject, Sendable {
    func cancel()
}

private final class DispatchSchedule: CancellableSchedule, @unchecked Sendable {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() { workItem.cancel() }
}

struct DispatchSessionCompletionScheduler: SessionCompletingScheduling {
    let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue(label: "com.rohitsandadi.astra.session-transition")) {
        self.queue = queue
    }

    func schedule(at date: Date, _ action: @escaping @Sendable () -> Void) -> any CancellableSchedule {
        let workItem = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + max(0, date.timeIntervalSinceNow), execute: workItem)
        return DispatchSchedule(workItem: workItem)
    }
}

protocol ApplicationInstallationProviding: Sendable {
    func isInstalled(bundleIdentifier: String) -> Bool
}

struct SystemApplicationInstallationProvider: ApplicationInstallationProviding {
    func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}

/// The launch agent's source of truth. Session transitions and interruption
/// challenges remain valid even while the UI is not running.
final class EnforcementCoordinator: BrowserPollingDelegate, @unchecked Sendable {
    private let applicationBlocker: ApplicationBlocker
    private let browserPoller: BrowserPoller
    private let blockPageServer: BlockPageServing
    private let sessionStore: SessionPersisting
    private let completionScheduler: SessionCompletingScheduling
    private let installationProvider: ApplicationInstallationProviding
    private let permissionRequester: BrowserPermissionRequesting
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    private var engine = FocusSessionEngine()
    private var completion: (any CancellableSchedule)?
    private var isEnforcing = false
    private var wakeObserver: NSObjectProtocol?

    init(
        applicationBlocker: ApplicationBlocker = ApplicationBlocker(),
        browserPoller: BrowserPoller = BrowserPoller(),
        blockPageServer: BlockPageServing = LoopbackHTTPBlockPageServer(),
        sessionStore: SessionPersisting = JSONSessionStore(),
        completionScheduler: SessionCompletingScheduling = DispatchSessionCompletionScheduler(),
        installationProvider: ApplicationInstallationProviding = SystemApplicationInstallationProvider(),
        permissionRequester: BrowserPermissionRequesting = AppleEventBrowserPermissionRequester(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.applicationBlocker = applicationBlocker
        self.browserPoller = browserPoller
        self.blockPageServer = blockPageServer
        self.sessionStore = sessionStore
        self.completionScheduler = completionScheduler
        self.installationProvider = installationProvider
        self.permissionRequester = permissionRequester
        self.now = now
        browserPoller.delegate = self
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reconcileAfterWake()
        }
    }

    func restore() throws {
        guard let persisted = try sessionStore.load() else { return }
        let restored = try FocusSessionEngine(restoring: persisted, at: now())
        guard let session = restored.session, !session.status.isTerminal else {
            try sessionStore.clear()
            return
        }
        lock.withLock { engine = restored }

        if session.status == .active {
            enableEnforcement(for: session)
        }
        EnforcerLog.lifecycle.notice("Restored active focus session")
        scheduleNextTransition(for: session)
        try sessionStore.save(currentSession()!)
    }

    func start(_ request: AstraStartSessionRequest) throws -> AstraSessionSnapshot {
        let started = try lock.withLock { () throws -> FocusSession in
            try engine.startSession(
                preset: request.preset,
                durationSeconds: request.durationSeconds,
                intention: request.intention,
                at: now(),
                enforcementHealth: baselineHealth()
            )
        }

        do {
            try sessionStore.save(started)
        } catch {
            lock.withLock { engine = FocusSessionEngine() }
            throw error
        }

        enableEnforcement(for: started)
        EnforcerLog.lifecycle.notice(
            "Started session with \(started.preset.blockedApplications.count, privacy: .public) apps and \(started.preset.domainRules.count, privacy: .public) domains"
        )
        let current = currentSession() ?? started
        scheduleNextTransition(for: current)
        // The initial session is already durable. A later health-only write must
        // not make the caller believe session startup failed after enforcement began.
        try? sessionStore.save(current)
        return snapshot()
    }

    func currentSnapshot() -> AstraSessionSnapshot {
        processTransitionIfNeeded()
        return snapshot()
    }

    /// Dispatch timers use an uptime clock, so a wake notification must reconcile
    /// the persisted wall-clock end date immediately after system sleep.
    func reconcileAfterWake() {
        processTransitionIfNeeded()
    }

    func permissionHealth() -> EnforcementHealth {
        lock.withLock { engine.session?.enforcementHealth } ?? baselineHealth()
    }

    func requestBrowserPermission(_ request: AstraBrowserPermissionRequest) -> EnforcementHealth {
        let requested = permissionRequester.permissionState(for: request.browser, askUserIfNeeded: true)
        EnforcerLog.browsers.notice(
            "Permission request for \(request.browser.displayName, privacy: .public) returned \(requested.permissionState.rawValue, privacy: .public)"
        )
        let refreshed = baselineHealth(replacing: requested)
        var sessionToPersist: FocusSession?
        lock.withLock {
            guard engine.session != nil else { return }
            try? engine.updateEnforcementHealth(refreshed)
            sessionToPersist = engine.session
        }
        if let sessionToPersist { try? sessionStore.save(sessionToPersist) }
        return refreshed
    }

    func requestInterruption(_ request: AstraInterruptionRequest) throws -> AstraInterruptionResponse {
        processTransitionIfNeeded()
        let result = try lock.withLock { () throws -> (InterruptionChallenge, FocusSession) in
            let challenge = try engine.requestInterruption(
                request.kind,
                breakDurationMinutes: request.breakDurationMinutes,
                at: now()
            )
            return (challenge, engine.session!)
        }
        try sessionStore.save(result.1)
        return AstraInterruptionResponse(challenge: result.0, snapshot: snapshot())
    }

    func commitInterruption(_ request: AstraCommitInterruptionRequest) throws -> AstraSessionSnapshot {
        processTransitionIfNeeded()
        let session = try lock.withLock { () throws -> FocusSession in
            try engine.commitInterruption(challengeID: request.challengeID, at: now())
        }

        switch session.status {
        case .onBreak:
            disableEnforcement()
            try sessionStore.save(session)
            scheduleNextTransition(for: session)
        case .completed, .endedEarly:
            disableEnforcement()
            cancelScheduledTransition()
            try sessionStore.clear()
        case .active:
            try sessionStore.save(session)
            scheduleNextTransition(for: session)
        }
        return snapshot()
    }

    func cancelInterruption(_ request: AstraCancelInterruptionRequest) throws -> AstraSessionSnapshot {
        processTransitionIfNeeded()
        let session = try lock.withLock { () throws -> FocusSession in
            try engine.cancelInterruption(challengeID: request.challengeID, at: now())
        }
        try sessionStore.save(session)
        return snapshot()
    }

    func browserPoller(_ poller: BrowserPoller, didUpdate browserHealth: BrowserEnforcementHealth) {
        var sessionToPersist: FocusSession?
        lock.withLock {
            guard var session = engine.session, !session.status.isTerminal else { return }
            var health = session.enforcementHealth
            if health.browserHealth.first(where: { $0.browser == browserHealth.browser }) == browserHealth {
                return
            }
            health.browserHealth.removeAll { $0.browser == browserHealth.browser }
            health.browserHealth.append(browserHealth)
            health.browserHealth.sort { $0.browser.rawValue < $1.browser.rawValue }
            health.lastCheckedAt = now()
            health.issues = Self.issues(from: health.browserHealth)
            try? engine.updateEnforcementHealth(health)
            session = engine.session ?? session
            sessionToPersist = session
        }
        if let sessionToPersist { try? sessionStore.save(sessionToPersist) }
    }

    private func baselineHealth(replacing replacement: BrowserEnforcementHealth? = nil) -> EnforcementHealth {
        let browsers = SupportedBrowser.allCases.map { browser in
            if replacement?.browser == browser { return replacement! }
            guard installationProvider.isInstalled(bundleIdentifier: browser.bundleIdentifier) else {
                return BrowserEnforcementHealth(
                    browser: browser,
                    isInstalled: false,
                    permissionState: .unavailable,
                    message: "\(browser.displayName) is not installed."
                )
            }
            return permissionRequester.permissionState(for: browser, askUserIfNeeded: false)
        }
        return EnforcementHealth(
            appBlockingOperational: true,
            browserHealth: browsers,
            issues: Self.issues(from: browsers),
            lastCheckedAt: now()
        )
    }

    private func enableEnforcement(for session: FocusSession) {
        let shouldStart = lock.withLock { () -> Bool in
            guard !isEnforcing else { return false }
            isEnforcing = true
            return true
        }
        guard shouldStart else { return }

        let bundleIdentifiers = Set(session.preset.blockedApplications.map(\.bundleIdentifier))
        applicationBlocker.start(blocking: bundleIdentifiers)

        guard !session.preset.domainRules.isEmpty else { return }
        do {
            let blockPageURL = try blockPageServer.start(for: session)
            browserPoller.start(domainRules: session.preset.domainRules, blockPageURL: blockPageURL)
        } catch {
            EnforcerLog.browsers.error("Local block page failed: \(error.localizedDescription, privacy: .public)")
            recordRuntimeIssue("The local block page could not start: \(error.localizedDescription)")
        }
    }

    private func disableEnforcement() {
        let shouldStop = lock.withLock { () -> Bool in
            guard isEnforcing else { return false }
            isEnforcing = false
            return true
        }
        guard shouldStop else { return }
        browserPoller.stop()
        applicationBlocker.stop()
        blockPageServer.stop()
    }

    private func processTransitionIfNeeded() {
        let transition = lock.withLock { () -> (previous: FocusSessionStatus, current: FocusSession)? in
            guard let current = engine.session,
                  !current.status.isTerminal else { return nil }
            let nextDate = current.status == .onBreak ? current.activeBreak?.endsAt : current.endDate
            guard let nextDate, now() >= nextDate else { return nil }
            let previous = current.status
            guard let refreshed = engine.refresh(at: now()) else { return nil }
            return (previous, refreshed)
        }
        guard let transition else { return }

        if transition.current.status.isTerminal {
            disableEnforcement()
            cancelScheduledTransition()
            try? sessionStore.clear()
        } else if transition.previous == .onBreak, transition.current.status == .active {
            try? sessionStore.save(transition.current)
            enableEnforcement(for: transition.current)
            scheduleNextTransition(for: transition.current)
        }
    }

    private func scheduleNextTransition(for session: FocusSession) {
        cancelScheduledTransition()
        guard !session.status.isTerminal else { return }
        let date = session.status == .onBreak ? (session.activeBreak?.endsAt ?? session.endDate) : session.endDate
        let schedule = completionScheduler.schedule(at: date) { [weak self] in
            self?.processTransitionIfNeeded()
        }
        lock.withLock { completion = schedule }
    }

    private func cancelScheduledTransition() {
        let scheduled = lock.withLock { () -> (any CancellableSchedule)? in
            defer { completion = nil }
            return completion
        }
        scheduled?.cancel()
    }

    private func recordRuntimeIssue(_ issue: String) {
        var sessionToPersist: FocusSession?
        lock.withLock {
            guard var health = engine.session?.enforcementHealth else { return }
            if !health.issues.contains(issue) { health.issues.append(issue) }
            health.lastCheckedAt = now()
            try? engine.updateEnforcementHealth(health)
            sessionToPersist = engine.session
        }
        if let sessionToPersist { try? sessionStore.save(sessionToPersist) }
    }

    private func snapshot() -> AstraSessionSnapshot {
        lock.withLock {
            let session = engine.session
            return AstraSessionSnapshot(
                session: session,
                enforcementHealth: session?.enforcementHealth ?? baselineHealth()
            )
        }
    }

    private func currentSession() -> FocusSession? {
        lock.withLock { engine.session }
    }

    private static func issues(from health: [BrowserEnforcementHealth]) -> [String] {
        health.compactMap { item in
            switch item.permissionState {
            case .denied, .incompatible:
                item.message ?? "\(item.browser.displayName) browser enforcement is unavailable."
            case .unavailable, .notDetermined, .authorized:
                nil
            }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        cancelScheduledTransition()
        disableEnforcement()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
