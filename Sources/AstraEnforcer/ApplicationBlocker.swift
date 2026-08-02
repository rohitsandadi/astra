@preconcurrency import AppKit
import Foundation

protocol RunningApplicationControlling: AnyObject, Sendable {
    var bundleIdentifier: String? { get }
    var processIdentifier: pid_t { get }
    var isTerminated: Bool { get }
    @discardableResult func terminate() -> Bool
    @discardableResult func forceTerminate() -> Bool
}

final class SystemRunningApplication: RunningApplicationControlling, @unchecked Sendable {
    private let application: NSRunningApplication

    init(_ application: NSRunningApplication) {
        self.application = application
    }

    var bundleIdentifier: String? { application.bundleIdentifier }
    var processIdentifier: pid_t { application.processIdentifier }
    var isTerminated: Bool { application.isTerminated }
    func terminate() -> Bool { application.terminate() }
    func forceTerminate() -> Bool { application.forceTerminate() }
}

protocol WorkspaceApplicationProviding: Sendable {
    var runningApplications: [any RunningApplicationControlling] { get }
    func observeLaunches(_ handler: @escaping @Sendable (any RunningApplicationControlling) -> Void) -> NSObjectProtocol
    func removeObserver(_ token: NSObjectProtocol)
}

struct SystemWorkspaceApplicationProvider: WorkspaceApplicationProviding {
    var runningApplications: [any RunningApplicationControlling] {
        NSWorkspace.shared.runningApplications.map(SystemRunningApplication.init)
    }

    func observeLaunches(_ handler: @escaping @Sendable (any RunningApplicationControlling) -> Void) -> NSObjectProtocol {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            handler(SystemRunningApplication(application))
        }
    }

    func removeObserver(_ token: NSObjectProtocol) {
        NSWorkspace.shared.notificationCenter.removeObserver(token)
    }
}

protocol TerminationScheduling: Sendable {
    func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void)
}

struct DispatchTerminationScheduler: TerminationScheduling {
    let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue(label: "com.rohitsandadi.astra.app-termination")) {
        self.queue = queue
    }

    func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void) {
        queue.asyncAfter(deadline: .now() + interval, execute: action)
    }
}

/// Observes process launches and closes applications selected by the active session.
final class ApplicationBlocker: @unchecked Sendable {
    static let protectedBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        "com.apple.systemuiserver",
        "com.rohitsandadi.astra",
        "com.rohitsandadi.astra.enforcer"
    ]

    private let workspace: WorkspaceApplicationProviding
    private let scheduler: TerminationScheduling
    private let gracePeriod: TimeInterval
    private let lock = NSLock()
    private var blockedBundleIdentifiers: Set<String> = []
    private var launchObserver: NSObjectProtocol?
    private var pendingProcessIdentifiers: Set<pid_t> = []

    init(
        workspace: WorkspaceApplicationProviding = SystemWorkspaceApplicationProvider(),
        scheduler: TerminationScheduling = DispatchTerminationScheduler(),
        gracePeriod: TimeInterval = 2
    ) {
        self.workspace = workspace
        self.scheduler = scheduler
        self.gracePeriod = gracePeriod
    }

    func start(blocking bundleIdentifiers: Set<String>) {
        stop()
        let safeIdentifiers = bundleIdentifiers.subtracting(Self.protectedBundleIdentifiers)
        lock.withLock { blockedBundleIdentifiers = safeIdentifiers }

        let observer = workspace.observeLaunches { [weak self] application in
            self?.evaluate(application)
        }
        lock.withLock { launchObserver = observer }
        workspace.runningApplications.forEach(evaluate)
    }

    func stop() {
        let observer = lock.withLock { () -> NSObjectProtocol? in
            blockedBundleIdentifiers = []
            pendingProcessIdentifiers = []
            defer { launchObserver = nil }
            return launchObserver
        }
        if let observer { workspace.removeObserver(observer) }
    }

    func evaluate(_ application: any RunningApplicationControlling) {
        guard let identifier = application.bundleIdentifier,
              !Self.protectedBundleIdentifiers.contains(identifier),
              lock.withLock({ blockedBundleIdentifiers.contains(identifier) }),
              !application.isTerminated else {
            return
        }

        let pid = application.processIdentifier
        let shouldTerminate = lock.withLock { pendingProcessIdentifiers.insert(pid).inserted }
        guard shouldTerminate else { return }

        let requestedGracefulTermination = application.terminate()
        EnforcerLog.applications.notice(
            "Requested termination of \(identifier, privacy: .public); accepted=\(requestedGracefulTermination, privacy: .public)"
        )
        scheduler.schedule(after: gracePeriod) { [weak self, weak application] in
            guard let self, let application else { return }
            let remainsBlocked = self.lock.withLock {
                self.pendingProcessIdentifiers.remove(pid)
                return application.bundleIdentifier.map(self.blockedBundleIdentifiers.contains) ?? false
            }
            if remainsBlocked && !application.isTerminated {
                _ = application.forceTerminate()
                EnforcerLog.applications.notice("Force-terminated blocked app \(identifier, privacy: .public)")
            }
        }
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
