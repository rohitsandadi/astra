import AppKit
import Foundation
import SwiftUI

@MainActor
final class AstraAppModel: ObservableObject {
    static let currentSetupVersion = 3

    @Published var selectedDestination: AstraDestination = .focus
    @Published private(set) var presets: [AstraPreset]
    @Published var selectedPresetID: UUID?
    @Published var durationMinutes = 45
    @Published var difficulty: AstraDifficulty = .commitment
    @Published private(set) var activeSession: AstraFocusSession?
    @Published private(set) var interruptionChallenge: AstraInterruptionChallenge?
    @Published private(set) var health = AstraEnforcementHealth(
        helperAvailable: false,
        browserPermissions: AstraBrowser.allCases.map {
            AstraBrowserPermission(browser: $0, status: .notRequested)
        }
    )
    @Published var isBusy = false
    @Published var alertMessage: String?
    @Published var showsOnboarding: Bool
    @Published var updateChecksEnabled: Bool {
        didSet {
            defaults.set(updateChecksEnabled, forKey: Keys.updateChecksEnabled)
            if updateChecksEnabled {
                Task { await checkForUpdates(force: true) }
            } else {
                updateStatusMessage = nil
                availableUpdateURL = nil
            }
        }
    }
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var updateStatusMessage: String?
    @Published private(set) var availableUpdateURL: URL?

    private let client: any AstraEnforcerClient
    private let defaults: UserDefaults
    private var didBootstrap = false
    private var verifiedBrowsers: Set<AstraBrowser> = []

    init(
        client: any AstraEnforcerClient = AstraLocalEnforcerClient(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
        self.updateChecksEnabled = defaults.bool(forKey: Keys.updateChecksEnabled)
        self.showsOnboarding = defaults.integer(forKey: Keys.completedSetupVersion)
            < Self.currentSetupVersion
        self.verifiedBrowsers = Set(
            (defaults.stringArray(forKey: Keys.verifiedBrowsers) ?? [])
                .compactMap(AstraBrowser.init(rawValue:))
        )

        if let data = defaults.data(forKey: Keys.presets),
           let saved = try? JSONDecoder().decode([AstraPreset].self, from: data),
           !saved.isEmpty {
            presets = saved
        } else {
            presets = [.starter]
        }

        let savedID = defaults.string(forKey: Keys.selectedPresetID).flatMap(UUID.init(uuidString:))
        selectedPresetID = presets.contains(where: { $0.id == savedID }) ? savedID : presets.first?.id
        if let preset = selectedPreset {
            durationMinutes = preset.durationMinutes
            difficulty = preset.difficulty
        }
    }

    var selectedPreset: AstraPreset? {
        presets.first(where: { $0.id == selectedPresetID })
    }

    var canStartFocus: Bool {
        activeSession == nil
            && !isBusy
            && selectedPreset != nil
            && durationMinutes >= 5
            && selectionIsReady
    }

    var selectionRequiresProtection: Bool {
        guard let selectedPreset else { return false }
        return !selectedPreset.applications.isEmpty || !selectedPreset.domains.isEmpty
    }

    var startBlockerReason: String? {
        guard activeSession == nil else { return "A focus session is already running." }
        guard let selectedPreset else { return "Choose a routine first." }
        guard durationMinutes >= 5 else { return "Choose at least five minutes." }
        guard selectionRequiresProtection else { return nil }
        guard health.helperAvailable else {
            return "Set up app blocking before starting this routine."
        }
        if !selectedPreset.domains.isEmpty && !health.allInstalledBrowsersReady {
            return "Allow browser access before starting this routine."
        }
        return nil
    }

    var runningBlockedApplications: [AstraBlockedApplication] {
        guard let selectedPreset else { return [] }
        let runningIdentifiers = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        return selectedPreset.applications.filter {
            runningIdentifiers.contains($0.bundleIdentifier)
        }
    }

    var browserVerificationNeeded: Bool {
        guard let selectedPreset else { return false }
        return !selectedPreset.domains.isEmpty && !health.allInstalledBrowsersReady
    }

    var readinessTitle: String {
        if !selectionRequiresProtection { return "Timer ready" }
        if !health.helperAvailable { return "Setup needed" }
        if browserVerificationNeeded { return "Browser check needed" }
        return "Blocking ready"
    }

    var selectionIsReady: Bool {
        return !selectionRequiresProtection || (health.helperAvailable && !browserVerificationNeeded)
    }

    var setupCanComplete: Bool {
        let agentStatus = AstraAgentRegistrationService.shared.status
        return agentStatus == .enabled
            && health.helperAvailable
            && health.allInstalledBrowsersReady
    }

    func bootstrap() async {
        guard !CommandLine.arguments.contains("--disable-protection"),
              !CommandLine.arguments.contains("--enable-protection"),
              !CommandLine.arguments.contains("--protection-status")
        else { return }
        guard !didBootstrap else { return }
        didBootstrap = true
        await AstraAgentRegistrationService.shared.invalidateOutdatedRegistrationIfNeeded()
        await refreshHealth()
        await refreshSessionFromClient()
        if updateChecksEnabled {
            await checkForUpdates(force: false)
        }
    }

    func refreshSessionFromClient() async {
        do {
            activeSession = try await client.currentSession()
            if interruptionChallenge == nil {
                interruptionChallenge = activeSession?.pendingInterruption
            }
        } catch {
            show(error)
        }
    }

    func refreshHealth() async {
        apply(await client.permissionHealth())
    }

    func selectPreset(_ id: UUID?) {
        selectedPresetID = id
        defaults.set(id?.uuidString, forKey: Keys.selectedPresetID)
        guard let preset = selectedPreset else { return }
        durationMinutes = preset.durationMinutes
        difficulty = preset.difficulty
    }

    func upsert(_ preset: AstraPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        persistPresets()
        selectPreset(preset.id)
    }

    func deletePreset(_ preset: AstraPreset) {
        guard presets.count > 1 else {
            alertMessage = "Astra keeps at least one routine."
            return
        }
        presets.removeAll(where: { $0.id == preset.id })
        persistPresets()
        if selectedPresetID == preset.id {
            selectPreset(presets.first?.id)
        }
    }

    func startFocus() async {
        guard !isBusy, let preset = selectedPreset, canStartFocus else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            activeSession = try await client.startSession(
                AstraFocusRequest(
                    preset: preset,
                    intention: "",
                    durationMinutes: durationMinutes,
                    difficulty: difficulty
                )
            )
            interruptionChallenge = nil
            selectedDestination = .focus
        } catch {
            show(error)
        }
    }

    func beginInterruption(_ kind: AstraInterruptionKind) async {
        guard let activeSession else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            interruptionChallenge = try await client.beginInterruption(for: activeSession, kind: kind)
        } catch {
            show(error)
        }
    }

    @discardableResult
    func commitInterruption() async -> Bool {
        guard let activeSession, let interruptionChallenge else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            self.activeSession = try await client.commitInterruption(
                interruptionChallenge,
                session: activeSession
            )
            self.interruptionChallenge = nil
            return true
        } catch {
            show(error)
            return false
        }
    }

    func cancelInterruption() async {
        guard let interruptionChallenge else { return }
        do {
            try await client.cancelInterruption(interruptionChallenge)
            self.interruptionChallenge = nil
        } catch {
            show(error)
        }
    }

    func requestPermission(for browser: AstraBrowser) async {
        guard AstraAgentRegistrationService.shared.status == .enabled else {
            alertMessage = "Enable app blocking before allowing browser access."
            return
        }
        isBusy = true
        let status = await client.requestAutomationPermission(for: browser)
        if status == .ready { verifiedBrowsers.insert(browser) }
        apply(await client.permissionHealth())
        isBusy = false
        if status != .ready, status != .notInstalled {
            alertMessage = "macOS did not allow access to \(browser.displayName). Try again or review Privacy & Security → Automation in System Settings."
        }
    }

    func waitForHelper() async {
        await AstraAgentRegistrationService.shared.invalidateOutdatedRegistrationIfNeeded()
        for _ in 0..<16 {
            AstraAgentRegistrationService.shared.refresh()
            apply(await client.permissionHealth())
            if health.helperAvailable { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if AstraAgentRegistrationService.shared.status == .enabled {
            alertMessage = "App blocking isn't responding. Reopen Astra from Applications and try again."
        }
    }

    func checkForUpdates(force: Bool) async {
        if !force,
           let lastCheck = defaults.object(forKey: Keys.lastUpdateCheck) as? Date,
           Date.now.timeIntervalSince(lastCheck) < 24 * 60 * 60 {
            return
        }

        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"

        do {
            let release = try await AstraUpdateChecker().latestRelease(
                currentVersion: currentVersion
            )
            defaults.set(Date.now, forKey: Keys.lastUpdateCheck)
            if AstraUpdateChecker.isNewer(release.tagName, than: currentVersion) {
                updateStatusMessage = "Astra \(release.tagName) is available."
                availableUpdateURL = release.pageURL
            } else {
                updateStatusMessage = "Astra \(currentVersion) is up to date."
                availableUpdateURL = nil
            }
        } catch {
            updateStatusMessage = error.localizedDescription
            availableUpdateURL = nil
        }
    }

    func completeOnboarding() {
        guard setupCanComplete else {
            alertMessage = "Enable app blocking and allow each installed browser before continuing."
            return
        }
        showsOnboarding = false
        defaults.set(Self.currentSetupVersion, forKey: Keys.completedSetupVersion)
    }

    func reopenOnboarding() {
        showsOnboarding = true
    }

    func dismissOnboarding() {
        showsOnboarding = false
    }

    func show(_ error: Error) {
        alertMessage = error.localizedDescription
    }

    private func persistPresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Keys.presets)
    }

    private func apply(_ freshHealth: AstraEnforcementHealth) {
        var merged = freshHealth
        for index in merged.browserPermissions.indices {
            let permission = merged.browserPermissions[index]
            switch permission.status {
            case .ready:
                verifiedBrowsers.insert(permission.browser)
            case .denied, .notInstalled:
                verifiedBrowsers.remove(permission.browser)
            case .notRequested where verifiedBrowsers.contains(permission.browser):
                merged.browserPermissions[index].status = .ready
                merged.browserPermissions[index].detail = "Previously allowed; Astra rechecks when the browser opens."
            case .notRequested:
                break
            }
        }
        defaults.set(verifiedBrowsers.map(\.rawValue).sorted(), forKey: Keys.verifiedBrowsers)
        health = merged
    }

    private enum Keys {
        static let presets = "astra.presets.v1"
        static let selectedPresetID = "astra.selected-preset-id"
        static let completedSetupVersion = "astra.completed-setup-version"
        static let updateChecksEnabled = "astra.update-checks-enabled"
        static let lastUpdateCheck = "astra.last-update-check"
        static let verifiedBrowsers = "astra.verified-browsers.v1"
    }
}
