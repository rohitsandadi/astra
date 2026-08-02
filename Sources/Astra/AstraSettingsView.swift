import AppKit
import SwiftUI

struct AstraSettingsView: View {
    @ObservedObject var model: AstraAppModel
    @ObservedObject private var agent = AstraAgentRegistrationService.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraMetrics.pageSpacing) {
                AstraPageHeader(
                    eyebrow: "Local controls",
                    title: "Settings",
                    detail: "Protection, privacy, and updates—without an account or cloud service."
                )

                if !model.setupCanComplete {
                    AstraStatusBanner(
                        title: "Protection setup is incomplete",
                        detail: "Enable the background helper and allow every installed supported browser.",
                        isReady: false,
                        actionTitle: "Review setup",
                        action: { model.reopenOnboarding() }
                    )
                }

                settingsGroup(
                    title: "Protection",
                    detail: "A user-level background item holds app and website blocks after the window closes."
                ) {
                    settingsRow(icon: "shield.lefthalf.filled") {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Background Protection").font(.body.weight(.medium))
                            Text(helperDetail).font(.caption).foregroundStyle(.secondary)
                            if let error = agent.errorMessage {
                                Text(error).font(.caption).textSelection(.enabled)
                            }
                        }
                    } trailing: {
                        agentAction
                    }

                    Divider().padding(.leading, 45)

                    VStack(spacing: 0) {
                        ForEach(model.health.browserPermissions) { permission in
                            AstraBrowserRow(
                                permission: permission,
                                helperReady: model.health.helperAvailable,
                                isBusy: model.isBusy
                            ) {
                                Task { await model.requestPermission(for: permission.browser) }
                            }
                            if permission.id != model.health.browserPermissions.last?.id {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                }

                settingsGroup(
                    title: "Updates",
                    detail: "GitHub Releases is Astra's only update source."
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Check periodically for new versions", isOn: $model.updateChecksEnabled)
                            .toggleStyle(.switch)
                            .tint(.astraAccent)
                        Text("Astra checks release metadata only when enabled and never installs silently.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let status = model.updateStatusMessage {
                            Text(status).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Check now", systemImage: "arrow.clockwise") {
                                Task { await model.checkForUpdates(force: true) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isCheckingForUpdates)

                            if let updateURL = model.availableUpdateURL {
                                Button("Download update", systemImage: "arrow.down.circle") {
                                    openURL(updateURL)
                                }
                                .astraPrimaryButton()
                            } else {
                                Button("GitHub Releases", systemImage: "arrow.up.right.square") {
                                    openURL(URL(string: "https://github.com/rohitsandadi/astra/releases")!)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                settingsGroup(
                    title: "Privacy & accessibility",
                    detail: "Astra follows macOS motion, transparency, contrast, and keyboard settings."
                ) {
                    VStack(alignment: .leading, spacing: 11) {
                        Label("Presets and active-session state stay on this Mac.", systemImage: "internaldrive")
                        Label("Browser automation reads only the foreground tab while a website block is active.", systemImage: "eye.slash")
                        Button("Run first-time setup again") { model.reopenOnboarding() }
                            .buttonStyle(.bordered)
                    }
                    .font(.callout)
                }

                settingsGroup(
                    title: "About Astra",
                    detail: "Open-source software licensed under GPL-3.0."
                ) {
                    HStack {
                        HStack(spacing: 11) {
                            AstraBrandMark(size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Astra \(version)").font(.body.weight(.medium))
                                Text("Focus, locally.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Source code") {
                            openURL(URL(string: "https://github.com/rohitsandadi/astra")!)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(AstraMetrics.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            agent.refresh()
            Task {
                if agent.status == .enabled { await model.waitForHelper() }
                else { await model.refreshHealth() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            agent.refresh()
            Task {
                if agent.status == .enabled { await model.waitForHelper() }
                else { await model.refreshHealth() }
            }
        }
    }

    @ViewBuilder
    private var agentAction: some View {
        switch agent.status {
        case .enabled:
            HStack(spacing: 8) {
                if model.health.helperAvailable {
                    AstraStatusPill(title: "Ready", isReady: true)
                } else {
                    ProgressView().controlSize(.small)
                }
                Button("Disable") {
                    Task {
                        await agent.unregister()
                        await model.refreshHealth()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(agent.isWorking || model.activeSession != nil)
            }
        case .notRegistered:
            Button("Enable") { enableAgent() }
                .buttonStyle(.bordered)
                .disabled(agent.isWorking)
        case .requiresApproval:
            Button("Open System Settings") { agent.openLoginItemSettings() }
                .buttonStyle(.bordered)
        case .requiresInstall:
            Button("Open Applications") { agent.openApplicationsFolder() }
                .buttonStyle(.bordered)
        case .unavailable:
            AstraStatusPill(title: "Unavailable", isReady: false)
        }
    }

    private var helperDetail: String {
        if agent.status == .enabled, !model.health.helperAvailable {
            return "Enabled, but the helper has not responded yet."
        }
        return agent.status.detail
    }

    private func settingsGroup<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .astraSurface(cornerRadius: 14, padding: 16)
    }

    private func settingsRow<Content: View, Trailing: View>(
        icon: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.astraAccent)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            content()
            Spacer(minLength: 12)
            trailing()
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private func enableAgent() {
        agent.register()
        Task { await model.waitForHelper() }
    }
}
