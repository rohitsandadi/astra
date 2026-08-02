import AppKit
import SwiftUI

struct AstraSettingsView: View {
    @ObservedObject var model: AstraAppModel
    @ObservedObject private var agent = AstraAgentRegistrationService.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 32, weight: .semibold))
                    .tracking(-0.7)

                if !model.setupCanComplete {
                    AstraStatusBanner(
                        title: "Finish setup",
                        detail: "Allow app and browser access before starting a routine.",
                        isReady: false,
                        actionTitle: "Open setup",
                        action: { model.reopenOnboarding() }
                    )
                }

                if agent.errorMessage != nil {
                    Label("Astra couldn't update app blocking. Try again or open System Settings.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingsGroup(title: "Blocking") {
                    appBlockingRow

                    ForEach(installedBrowsers) { permission in
                        Divider()
                            .padding(.leading, 46)
                        browserRow(permission)
                    }
                }

                settingsGroup(title: "Updates") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Check for updates automatically", isOn: $model.updateChecksEnabled)
                            .toggleStyle(.switch)
                            .tint(.astraAccent)

                        if let status = model.updateStatusMessage {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Button("Check Now", systemImage: "arrow.clockwise") {
                                Task { await model.checkForUpdates(force: true) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isCheckingForUpdates)

                            if let updateURL = model.availableUpdateURL {
                                Button("Download", systemImage: "arrow.down.circle") {
                                    openURL(updateURL)
                                }
                                .astraPrimaryButton()
                            } else {
                                Button("Releases", systemImage: "arrow.up.right.square") {
                                    openURL(URL(string: "https://github.com/rohitsandadi/astra/releases")!)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                settingsGroup(title: "About") {
                    HStack(spacing: 12) {
                        AstraBrandMark(size: 42)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Astra")
                                .font(.body.weight(.medium))
                            Text("Version \(version) · GPL-3.0")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Source Code") {
                            openURL(URL(string: "https://github.com/rohitsandadi/astra")!)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: AstraMetrics.contentWidth, alignment: .leading)
            .padding(AstraMetrics.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: refreshAccess)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccess()
        }
    }

    private var appBlockingRow: some View {
        HStack(spacing: 13) {
            Image(systemName: "app.badge.checkmark")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.astraAccent)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))

            Text("App blocking")
                .font(.body.weight(.medium))

            Spacer(minLength: 16)
            appBlockingAction
        }
        .padding(.vertical, 8)
    }

    private func browserRow(_ permission: AstraBrowserPermission) -> some View {
        HStack(spacing: 13) {
            AstraBrowserIcon(browser: permission.browser, size: 34)

            Text(permission.browser.displayName)
                .font(.body.weight(.medium))

            Spacer(minLength: 16)
            browserAction(for: permission)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var appBlockingAction: some View {
        switch agent.status {
        case .enabled:
            HStack(spacing: 6) {
                if model.health.helperAvailable {
                    readyLabel
                } else {
                    Button("Retry") {
                        Task { await model.waitForHelper() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(agent.isWorking)
                }

                Menu {
                    Button("Turn Off App Blocking", role: .destructive) {
                        Task {
                            await agent.unregister()
                            await model.refreshHealth()
                        }
                    }
                    .disabled(model.activeSession != nil)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(agent.isWorking)
                .help(model.activeSession == nil ? "More options" : "App blocking cannot be turned off during a routine.")
            }
        case .notRegistered:
            Button("Enable", action: enableAgent)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(agent.isWorking)
        case .requiresApproval:
            Button("Open Settings") {
                agent.openLoginItemSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .requiresInstall:
            Button("Open Applications") {
                agent.openApplicationsFolder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .unavailable:
            Text("Unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func browserAction(for permission: AstraBrowserPermission) -> some View {
        switch permission.status {
        case .ready:
            readyLabel
        case .notRequested, .denied:
            Button("Allow") {
                Task { await model.requestPermission(for: permission.browser) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isBusy || !model.health.helperAvailable)
        case .notInstalled:
            EmptyView()
        }
    }

    private var readyLabel: some View {
        Label("Ready", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.astraAccent)
    }

    private func settingsGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .astraSurface(cornerRadius: AstraMetrics.cornerRadius, padding: 16)
    }

    private var installedBrowsers: [AstraBrowserPermission] {
        model.health.browserPermissions.filter { permission in
            permission.status != .notInstalled
                && NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: permission.browser.bundleIdentifier
                ) != nil
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private func refreshAccess() {
        agent.refresh()
        Task {
            if agent.status == .enabled {
                await model.waitForHelper()
            } else {
                await model.refreshHealth()
            }
        }
    }

    private func enableAgent() {
        agent.register()
        if agent.errorMessage != nil {
            model.alertMessage = "Astra couldn't enable app blocking. Try again or open System Settings."
        }
        Task { await model.waitForHelper() }
    }
}
