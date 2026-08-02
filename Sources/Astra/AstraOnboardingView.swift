import AppKit
import SwiftUI

struct AstraOnboardingView: View {
    @ObservedObject var model: AstraAppModel
    @ObservedObject private var agent = AstraAgentRegistrationService.shared

    var body: some View {
        ZStack {
            AstraWindowBackground()

            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    AstraBrandMark(size: 52)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Set up Astra")
                            .font(.system(size: 27, weight: .semibold))
                            .tracking(-0.5)
                        Text("Allow access to block apps and websites.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                accessList

                if agent.errorMessage != nil {
                    Label("Astra couldn't enable app blocking. Try again or open System Settings.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Later") { model.dismissOnboarding() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Done") {
                        model.completeOnboarding()
                    }
                    .keyboardShortcut(.defaultAction)
                    .astraPrimaryButton()
                    .disabled(!model.setupCanComplete || agent.isWorking || model.isBusy)
                }
            }
            .padding(26)
        }
        .frame(width: 540)
        .tint(.astraAccent)
        .preferredColorScheme(.dark)
        .onAppear(perform: refreshAccess)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccess()
        }
    }

    private var accessList: some View {
        VStack(spacing: 0) {
            accessRow(
                title: "App blocking",
                systemImage: "app.badge.checkmark"
            ) {
                appBlockingAction
            }

            ForEach(installedBrowsers) { permission in
                Divider()
                    .padding(.leading, 46)

                browserRow(permission)
            }
        }
        .astraSurface(
            cornerRadius: AstraMetrics.cornerRadius,
            emphasized: !model.setupCanComplete,
            padding: 8
        )
    }

    private func accessRow<Trailing: View>(
        title: String,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.astraAccent)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))

            Text(title)
                .font(.body.weight(.medium))

            Spacer(minLength: 16)
            trailing()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
    }

    private func browserRow(_ permission: AstraBrowserPermission) -> some View {
        HStack(spacing: 13) {
            AstraBrowserIcon(browser: permission.browser, size: 34)

            Text(permission.browser.displayName)
                .font(.body.weight(.medium))

            Spacer(minLength: 16)

            browserAction(for: permission)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var appBlockingAction: some View {
        switch agent.status {
        case .enabled:
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
        case .notRegistered:
            Button("Enable", action: enableAgent)
                .buttonStyle(.borderedProminent)
                .tint(.astraAccent)
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

    private var installedBrowsers: [AstraBrowserPermission] {
        model.health.browserPermissions.filter { permission in
            permission.status != .notInstalled
                && NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: permission.browser.bundleIdentifier
                ) != nil
        }
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
