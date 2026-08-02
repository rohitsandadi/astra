import Foundation
import ServiceManagement
import XCTest
@testable import Astra

final class AstraUIModelTests: XCTestCase {
    func testBrowserReadinessRequiresEveryInstalledSupportedBrowser() {
        let partial = AstraEnforcementHealth(
            helperAvailable: true,
            browserPermissions: [
                .init(browser: .safari, status: .ready),
                .init(browser: .chrome, status: .notInstalled),
                .init(browser: .dia, status: .notRequested)
            ]
        )

        XCTAssertEqual(partial.installedBrowserCount, 2)
        XCTAssertEqual(partial.readyBrowserCount, 1)
        XCTAssertFalse(partial.allInstalledBrowsersReady)
    }

    func testUninstalledBrowsersDoNotBlockReadiness() {
        let ready = AstraEnforcementHealth(
            helperAvailable: true,
            browserPermissions: [
                .init(browser: .safari, status: .ready),
                .init(browser: .chrome, status: .notInstalled),
                .init(browser: .dia, status: .ready)
            ]
        )

        XCTAssertTrue(ready.allInstalledBrowsersReady)
    }

    func testApplicationCatalogDiscoversAndSortsValidBundles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try createApplication(named: "Zeta", identifier: "example.zeta", in: root)
        try createApplication(named: "Alpha", identifier: "example.alpha", in: root)

        let result = AstraApplicationCatalog.discoverApplications(roots: [root])

        XCTAssertEqual(result.map(\.displayName), ["Alpha", "Zeta"])
        XCTAssertEqual(Set(result.map(\.bundleIdentifier)), ["example.alpha", "example.zeta"])
    }

    func testApplicationCatalogExcludesProtectedBundles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try createApplication(named: "Finder", identifier: "com.apple.finder", in: root)

        XCTAssertTrue(AstraApplicationCatalog.discoverApplications(roots: [root]).isEmpty)
    }

    @MainActor
    func testPackagedUnregisteredAgentIsEnableableWhenAppIsInstalled() {
        let status = AstraAgentRegistrationService.resolveStatus(
            serviceStatus: .notRegistered,
            bundleURL: URL(fileURLWithPath: "/Applications/Astra.app"),
            fileExists: { _ in true }
        )

        XCTAssertEqual(status, .notRegistered)
    }

    @MainActor
    func testPackagedUnregisteredAgentRequestsInstallOutsideApplications() {
        let status = AstraAgentRegistrationService.resolveStatus(
            serviceStatus: .notRegistered,
            bundleURL: URL(fileURLWithPath: "/Users/test/Downloads/Astra.app"),
            fileExists: { _ in true }
        )

        XCTAssertEqual(status, .requiresInstall)
    }

    @MainActor
    func testNotFoundAgentRemainsUnavailable() {
        let status = AstraAgentRegistrationService.resolveStatus(
            serviceStatus: .notFound,
            bundleURL: URL(fileURLWithPath: "/Applications/Astra.app"),
            fileExists: { _ in true }
        )

        XCTAssertEqual(status, .unavailable)
    }

    @MainActor
    func testUnregisteredAgentWithoutBundledPlistRemainsUnavailable() {
        let status = AstraAgentRegistrationService.resolveStatus(
            serviceStatus: .notRegistered,
            bundleURL: URL(fileURLWithPath: "/Applications/Astra.app"),
            fileExists: { _ in false }
        )

        XCTAssertEqual(status, .unavailable)
    }

    @MainActor
    func testProtectedRoutineNeverBecomesReadyWithoutLiveHelper() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AstraAppModel(defaults: defaults)

        XCTAssertTrue(model.selectionRequiresProtection)
        XCTAssertFalse(model.selectionIsReady)
        XCTAssertFalse(model.setupCanComplete)
    }

    @MainActor
    func testTimerOnlyRoutineDoesNotRequireProtection() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AstraAppModel(defaults: defaults)
        let timerOnly = AstraPreset(
            name: "Timer only",
            durationMinutes: 25,
            difficulty: .flexible
        )

        model.upsert(timerOnly)

        XCTAssertFalse(model.selectionRequiresProtection)
        XCTAssertTrue(model.selectionIsReady)
    }

    @MainActor
    func testStartingRoutineUsesSavedValuesAndNoHiddenTitle() async {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = CapturingEnforcerClient()
        let model = AstraAppModel(client: client, defaults: defaults)
        let routine = AstraPreset(
            name: "This internal name must not become a session title",
            durationMinutes: 25,
            difficulty: .flexible
        )

        model.upsert(routine)
        await model.startFocus()

        XCTAssertEqual(client.lastStartRequest?.preset.id, routine.id)
        XCTAssertEqual(client.lastStartRequest?.durationMinutes, 25)
        XCTAssertEqual(client.lastStartRequest?.difficulty, .flexible)
        XCTAssertEqual(client.lastStartRequest?.intention, "")
    }

    func testRoutinePresentationDoesNotDependOnStoredName() {
        let first = AstraPreset(
            name: "Morning",
            domains: ["example.com"],
            durationMinutes: 45,
            difficulty: .commitment
        )
        var second = first
        second.name = "Completely different internal value"

        XCTAssertEqual(first.durationLabel, second.durationLabel)
        XCTAssertEqual(first.routineSummary, second.routineSummary)
        XCTAssertEqual(first.routineAccessibilityLabel, second.routineAccessibilityLabel)
        XCTAssertFalse(first.routineSummary.contains(first.name))
    }

    @MainActor
    func testRegistrationStatusCopyDoesNotExposeProcessInternals() {
        let forbidden = ["helper", "xpc", "background item", "protection"]

        for status in [
            AstraAgentRegistrationStatus.enabled,
            .notRegistered,
            .requiresApproval,
            .requiresInstall,
            .unavailable
        ] {
            let copy = status.detail.lowercased()
            for term in forbidden {
                XCTAssertFalse(copy.contains(term), "Found \(term) in: \(status.detail)")
            }
        }
    }

    private func createApplication(named name: String, identifier: String, in root: URL) throws {
        let contents = root
            .appendingPathComponent("\(name).app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleName": name,
            "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "AstraUIModelTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}

@MainActor
private final class CapturingEnforcerClient: AstraEnforcerClient {
    private let local = AstraLocalEnforcerClient()
    private(set) var lastStartRequest: AstraFocusRequest?

    func currentSession() async throws -> AstraFocusSession? {
        try await local.currentSession()
    }

    func startSession(_ request: AstraFocusRequest) async throws -> AstraFocusSession {
        lastStartRequest = request
        return try await local.startSession(request)
    }

    func beginInterruption(
        for session: AstraFocusSession,
        kind: AstraInterruptionKind
    ) async throws -> AstraInterruptionChallenge {
        try await local.beginInterruption(for: session, kind: kind)
    }

    func commitInterruption(
        _ challenge: AstraInterruptionChallenge,
        session: AstraFocusSession
    ) async throws -> AstraFocusSession? {
        try await local.commitInterruption(challenge, session: session)
    }

    func cancelInterruption(_ challenge: AstraInterruptionChallenge) async throws {
        try await local.cancelInterruption(challenge)
    }

    func permissionHealth() async -> AstraEnforcementHealth {
        AstraEnforcementHealth(
            helperAvailable: true,
            browserPermissions: AstraBrowser.allCases.map {
                AstraBrowserPermission(browser: $0, status: .ready)
            }
        )
    }

    func requestAutomationPermission(for browser: AstraBrowser) async -> AstraPermissionStatus {
        .ready
    }
}
