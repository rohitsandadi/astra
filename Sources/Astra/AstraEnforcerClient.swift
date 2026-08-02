import AppKit
import AstraCore
import Foundation

@MainActor
protocol AstraEnforcerClient: AnyObject {
    func currentSession() async throws -> AstraFocusSession?
    func startSession(_ request: AstraFocusRequest) async throws -> AstraFocusSession
    func beginInterruption(
        for session: AstraFocusSession,
        kind: AstraInterruptionKind
    ) async throws -> AstraInterruptionChallenge
    func commitInterruption(
        _ challenge: AstraInterruptionChallenge,
        session: AstraFocusSession
    ) async throws -> AstraFocusSession?
    func cancelInterruption(_ challenge: AstraInterruptionChallenge) async throws
    func permissionHealth() async -> AstraEnforcementHealth
    func requestAutomationPermission(for browser: AstraBrowser) async -> AstraPermissionStatus
}

/// An intentionally useful local fallback for previews and Swift Package runs.
/// It uses the same AstraCore state machine as the launch agent.
@MainActor
final class AstraLocalEnforcerClient: AstraEnforcerClient {
    private var engine = FocusSessionEngine()
    private var requestedPermissions: Set<AstraBrowser> = []

    func currentSession() async throws -> AstraFocusSession? {
        guard let session = engine.refresh(), !session.status.isTerminal else { return nil }
        return session
    }

    func startSession(_ request: AstraFocusRequest) async throws -> AstraFocusSession {
        var preset = request.preset
        preset.defaultDurationSeconds = request.durationMinutes * 60
        preset.difficulty = request.difficulty
        preset.updatedAt = .now
        return try engine.startSession(
            preset: preset,
            durationSeconds: request.durationMinutes * 60,
            intention: request.intention
        )
    }

    func beginInterruption(
        for session: AstraFocusSession,
        kind: AstraInterruptionKind
    ) async throws -> AstraInterruptionChallenge {
        switch kind {
        case .breakFor(let minutes):
            return try engine.requestInterruption(.takeBreak, breakDurationMinutes: minutes)
        case .endSession:
            return try engine.requestInterruption(.endSession)
        }
    }

    func commitInterruption(
        _ challenge: AstraInterruptionChallenge,
        session: AstraFocusSession
    ) async throws -> AstraFocusSession? {
        let updated = try engine.commitInterruption(challengeID: challenge.id)
        return updated.status.isTerminal ? nil : updated
    }

    func cancelInterruption(_ challenge: AstraInterruptionChallenge) async throws {
        _ = try engine.cancelInterruption(challengeID: challenge.id)
    }

    func permissionHealth() async -> AstraEnforcementHealth {
        let permissions = AstraBrowser.allCases.map { browser in
            let installed = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: browser.bundleIdentifier
            ) != nil
            let status: AstraPermissionStatus
            if !installed {
                status = .notInstalled
            } else if requestedPermissions.contains(browser) {
                status = .ready
            } else {
                status = .notRequested
            }
            return AstraBrowserPermission(browser: browser, status: status)
        }
        return AstraEnforcementHealth(helperAvailable: false, browserPermissions: permissions)
    }

    func requestAutomationPermission(for browser: AstraBrowser) async -> AstraPermissionStatus {
        guard NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: browser.bundleIdentifier
        ) != nil else {
            return .notInstalled
        }
        requestedPermissions.insert(browser)
        return .ready
    }
}

enum AstraClientFactory {
    @MainActor
    static func makeDefault() -> any AstraEnforcerClient {
        AstraResilientEnforcerClient(
            primary: AstraXPCEnforcerClient(),
            fallback: AstraLocalEnforcerClient()
        )
    }
}

@MainActor
final class AstraXPCEnforcerClient: AstraEnforcerClient {
    init() {}

    func currentSession() async throws -> AstraFocusSession? {
        let snapshot: AstraSessionSnapshot = try await call { proxy, reply in
            proxy.currentSnapshot(withReply: reply)
        }
        return snapshot.session?.status.isTerminal == false ? snapshot.session : nil
    }

    func startSession(_ request: AstraFocusRequest) async throws -> AstraFocusSession {
        var preset = request.preset
        preset.defaultDurationSeconds = request.durationMinutes * 60
        preset.difficulty = request.difficulty
        preset.updatedAt = .now
        let data = try AstraXPCJSONCodec.encode(
            AstraStartSessionRequest(
                preset: preset,
                durationSeconds: request.durationMinutes * 60,
                intention: request.intention
            )
        )
        let snapshot: AstraSessionSnapshot = try await call { proxy, reply in
            proxy.startSession(data, withReply: reply)
        }
        guard let session = snapshot.session, !session.status.isTerminal else {
            throw AstraRemoteClientError("The helper did not return the session it started.")
        }
        return session
    }

    func beginInterruption(
        for session: AstraFocusSession,
        kind: AstraInterruptionKind
    ) async throws -> AstraInterruptionChallenge {
        let request: AstraInterruptionRequest
        switch kind {
        case .breakFor(let minutes):
            request = AstraInterruptionRequest(kind: .takeBreak, breakDurationMinutes: minutes)
        case .endSession:
            request = AstraInterruptionRequest(kind: .endSession)
        }
        let data = try AstraXPCJSONCodec.encode(request)
        let response: AstraInterruptionResponse = try await call { proxy, reply in
            proxy.requestInterruption(data, withReply: reply)
        }
        return response.challenge
    }

    func commitInterruption(
        _ challenge: AstraInterruptionChallenge,
        session: AstraFocusSession
    ) async throws -> AstraFocusSession? {
        let data = try AstraXPCJSONCodec.encode(
            AstraCommitInterruptionRequest(challengeID: challenge.id)
        )
        let snapshot: AstraSessionSnapshot = try await call { proxy, reply in
            proxy.commitInterruption(data, withReply: reply)
        }
        return snapshot.session?.status.isTerminal == false ? snapshot.session : nil
    }

    func cancelInterruption(_ challenge: AstraInterruptionChallenge) async throws {
        let data = try AstraXPCJSONCodec.encode(
            AstraCancelInterruptionRequest(challengeID: challenge.id)
        )
        let _: AstraSessionSnapshot = try await call { proxy, reply in
            proxy.cancelInterruption(data, withReply: reply)
        }
    }

    func permissionHealth() async -> AstraEnforcementHealth {
        do {
            return Self.mapHealth(try await health())
        } catch {
            return AstraEnforcementHealth(
                helperAvailable: false,
                browserPermissions: Self.localBrowserDefaults,
                issues: ["The background helper did not respond."]
            )
        }
    }

    func requestAutomationPermission(for browser: AstraBrowser) async -> AstraPermissionStatus {
        do {
            let data = try AstraXPCJSONCodec.encode(AstraBrowserPermissionRequest(browser: browser))
            let health: EnforcementHealth = try await call { proxy, reply in
                proxy.requestBrowserPermission(data, withReply: reply)
            }
            return Self.mapHealth(health).browserPermissions
                .first(where: { $0.browser == browser })?.status ?? .denied
        } catch {
            return .denied
        }
    }

    func health() async throws -> EnforcementHealth {
        try await call { proxy, reply in
            proxy.permissionHealth(withReply: reply)
        }
    }

    private func call<Payload: Codable & Sendable>(
        _ operation: @escaping (
            AstraEnforcerXPCProtocol,
            @escaping (Data) -> Void
        ) -> Void
    ) async throws -> Payload {
        try await withCheckedThrowingContinuation { continuation in
            // A short-lived connection automatically recovers after a helper
            // restart; a retained NSXPCConnection stays invalid once its peer dies.
            let connection = NSXPCConnection(machServiceName: "com.rohitsandadi.astra.enforcer")
            connection.remoteObjectInterface = NSXPCInterface(with: AstraEnforcerXPCProtocol.self)
            connection.resume()
            let connectionBox = AstraXPCConnectionBox(connection)

            let replyBox = AstraXPCReplyBox(continuation: continuation)
            let errorHandler: @Sendable (Error) -> Void = { error in
                connectionBox.invalidate()
                replyBox.resume(throwing: error)
            }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler)
                as? AstraEnforcerXPCProtocol else {
                connection.invalidate()
                replyBox.resume(throwing: AstraRemoteClientError("The Astra helper is unavailable."))
                return
            }

            let replyHandler: @Sendable (Data) -> Void = { data in
                do {
                    let response = try AstraXPCJSONCodec.decode(
                        AstraXPCResponse<Payload>.self,
                        from: data
                    )
                    switch response {
                    case .success(let payload):
                        connectionBox.invalidate()
                        replyBox.resume(returning: payload)
                    case .failure(let error):
                        connectionBox.invalidate()
                        replyBox.resume(throwing: AstraRemoteClientError(error.message))
                    }
                } catch {
                    connectionBox.invalidate()
                    replyBox.resume(throwing: error)
                }
            }
            operation(proxy, replyHandler)
        }
    }

    fileprivate static func mapHealth(_ health: EnforcementHealth) -> AstraEnforcementHealth {
        let permissions = AstraBrowser.allCases.map { browser in
            guard let browserHealth = health.browserHealth.first(where: { $0.browser == browser }) else {
                return localBrowserDefaults.first(where: { $0.browser == browser })!
            }
            let status: AstraPermissionStatus
            if !browserHealth.isInstalled {
                status = .notInstalled
            } else {
                switch browserHealth.permissionState {
                case .authorized: status = .ready
                case .notDetermined: status = .notRequested
                case .denied, .incompatible, .unavailable: status = .denied
                }
            }
            return AstraBrowserPermission(
                browser: browser,
                status: status,
                detail: browserHealth.message
            )
        }
        return AstraEnforcementHealth(
            helperAvailable: health.appBlockingOperational,
            browserPermissions: permissions,
            issues: health.issues
        )
    }

    private static var localBrowserDefaults: [AstraBrowserPermission] {
        AstraBrowser.allCases.map { browser in
            AstraBrowserPermission(
                browser: browser,
                status: NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: browser.bundleIdentifier
                ) == nil ? .notInstalled : .notRequested,
                detail: nil
            )
        }
    }
}

@MainActor
final class AstraResilientEnforcerClient: AstraEnforcerClient {
    private let primary: AstraXPCEnforcerClient
    private let fallback: AstraLocalEnforcerClient
    /// Once a timer has started in the preview fallback, it must stay with that
    /// state machine for its lifetime. Otherwise helper registration midway
    /// through a session could make the UI appear to lose the timer.
    private var fallbackOwnsSession = false

    init(primary: AstraXPCEnforcerClient, fallback: AstraLocalEnforcerClient) {
        self.primary = primary
        self.fallback = fallback
    }

    func currentSession() async throws -> AstraFocusSession? {
        if fallbackOwnsSession {
            let session = try await fallback.currentSession()
            if session == nil { fallbackOwnsSession = false }
            return session
        }
        switch helperStatus {
        case .enabled:
            return try await primary.currentSession()
        case .unavailable:
            return try await fallback.currentSession()
        case .notRegistered, .requiresApproval, .requiresInstall:
            return nil
        }
    }

    func startSession(_ request: AstraFocusRequest) async throws -> AstraFocusSession {
        switch helperStatus {
        case .enabled:
            let session = try await primary.startSession(request)
            fallbackOwnsSession = false
            return session
        case .unavailable:
            // Raw SwiftPM launches do not contain the bundled LaunchAgent. Keeping
            // the local state machine here makes previews useful without weakening
            // the behavior of a packaged Astra.app.
            let session = try await fallback.startSession(request)
            fallbackOwnsSession = true
            return session
        case .notRegistered:
            throw AstraRemoteClientError(
                "Enable Astra's background helper in Settings before starting an enforced session."
            )
        case .requiresApproval:
            throw AstraRemoteClientError(
                "Approve Astra under System Settings → General → Login Items & Extensions before starting a session."
            )
        case .requiresInstall:
            throw AstraRemoteClientError(
                "Move Astra.app to Applications and reopen it before starting an enforced session."
            )
        }
    }

    func beginInterruption(
        for session: AstraFocusSession,
        kind: AstraInterruptionKind
    ) async throws -> AstraInterruptionChallenge {
        if fallbackOwnsSession {
            return try await fallback.beginInterruption(for: session, kind: kind)
        }
        return try await primary.beginInterruption(for: session, kind: kind)
    }

    func commitInterruption(
        _ challenge: AstraInterruptionChallenge,
        session: AstraFocusSession
    ) async throws -> AstraFocusSession? {
        let updated: AstraFocusSession?
        if fallbackOwnsSession {
            updated = try await fallback.commitInterruption(challenge, session: session)
        } else {
            updated = try await primary.commitInterruption(challenge, session: session)
        }
        if updated == nil { fallbackOwnsSession = false }
        return updated
    }

    func cancelInterruption(_ challenge: AstraInterruptionChallenge) async throws {
        if fallbackOwnsSession {
            try await fallback.cancelInterruption(challenge)
        } else {
            try await primary.cancelInterruption(challenge)
        }
    }

    func permissionHealth() async -> AstraEnforcementHealth {
        guard helperStatus == .enabled else {
            return await fallback.permissionHealth()
        }
        do {
            return AstraXPCEnforcerClient.mapHealth(try await primary.health())
        } catch {
            return await fallback.permissionHealth()
        }
    }

    func requestAutomationPermission(for browser: AstraBrowser) async -> AstraPermissionStatus {
        guard helperStatus == .enabled else { return .notRequested }
        return await primary.requestAutomationPermission(for: browser)
    }

    private var helperStatus: AstraAgentRegistrationStatus {
        AstraAgentRegistrationService.shared.status
    }
}

private struct AstraRemoteClientError: LocalizedError {
    var message: String

    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private final class AstraXPCReplyBox<Payload: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Payload, Error>?

    init(continuation: CheckedContinuation<Payload, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Payload) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Payload, Error>? {
        lock.lock()
        defer { lock.unlock() }
        defer { continuation = nil }
        return continuation
    }
}

private final class AstraXPCConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection

    init(_ connection: NSXPCConnection) {
        self.connection = connection
    }

    func invalidate() {
        connection.invalidate()
    }
}
