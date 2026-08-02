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
