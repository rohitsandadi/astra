import AppKit
import SwiftUI

struct AstraOnboardingView: View {
    @ObservedObject var model: AstraAppModel
    @ObservedObject private var agent = AstraAgentRegistrationService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    AstraBrandMark(size: 31)
                    Text("Astra").font(.headline)
                }
                Spacer()
                Text("SETUP \(page + 1) OF \(lastPage + 1)")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.25)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(.ultraThinMaterial)

            Divider()

            ZStack {
                AstraWindowBackground()
                pageContent
                    .id(page)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 12)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                pageIndicator
                Spacer()
                if page > 0 {
                    Button("Back") { move(to: page - 1) }
                        .buttonStyle(.plain)
                }
                Button(primaryActionTitle) { performPrimaryAction() }
                    .keyboardShortcut(.defaultAction)
                    .astraPrimaryButton()
                    .disabled(primaryActionDisabled)
            }
            .padding(18)
            .background(.ultraThinMaterial)
        }
        .frame(width: 760, height: 620)
        .tint(.astraAccent)
        .preferredColorScheme(.dark)
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
    private var pageContent: some View {
        switch page {
        case 0: welcome
        case 1: protection
        default: ready
        }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            AstraBrandMark(size: 92)
            VStack(spacing: 9) {
                Text("Focus without sending anything away.")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.7)
                    .multilineTextAlignment(.center)
                Text("Astra keeps distracting apps and websites outside your focus—entirely on this Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
            }
            HStack(spacing: 10) {
                trustPill("No account", systemImage: "person.crop.circle.badge.xmark")
                trustPill("No analytics", systemImage: "chart.bar.xaxis")
                trustPill("Open source", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        }
        .padding(44)
    }

    private var protection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AstraSectionHeading(
                    eyebrow: "Protection",
                    title: "Two local permissions. Nothing hidden.",
                    detail: "A background item keeps app blocking active. macOS Automation access lets Astra inspect and redirect only the current tab in each browser."
                )

                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: model.health.helperAvailable ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                        .font(.title3)
                        .foregroundStyle(model.health.helperAvailable ? Color.astraAccent : .secondary)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Background Protection").font(.headline)
                        Text(helperDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let error = agent.errorMessage {
                            Text(error).font(.caption).textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 12)
                    helperAction
                }
                .astraSurface(
                    cornerRadius: AstraMetrics.compactCornerRadius,
                    emphasized: !model.health.helperAvailable,
                    padding: 14
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Browser access").font(.headline)
                        Spacer()
                        Text("\(model.health.readyBrowserCount) of \(model.health.installedBrowserCount) ready")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Allow every installed supported browser so switching browsers cannot bypass a website block.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 5)

                    ForEach(model.health.browserPermissions) { permission in
                        AstraBrowserRow(
                            permission: permission,
                            helperReady: model.health.helperAvailable,
                            isBusy: model.isBusy
                        ) {
                            Task { await model.requestPermission(for: permission.browser) }
                        }
                        if permission.id != model.health.browserPermissions.last?.id { Divider() }
                    }
                }
                .astraSurface(cornerRadius: AstraMetrics.compactCornerRadius, padding: 14)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(34)
            .frame(maxWidth: .infinity)
        }
    }

    private var ready: some View {
        VStack(spacing: 22) {
            Image(systemName: model.setupCanComplete ? "checkmark" : "ellipsis")
                .font(.system(size: 33, weight: .medium))
                .foregroundStyle(model.setupCanComplete ? Color.astraAccent : .secondary)
                .frame(width: 74, height: 74)
                .background(Color.white.opacity(0.05), in: Circle())
                .overlay { Circle().stroke(Color.white.opacity(0.08), lineWidth: 1) }
            VStack(spacing: 9) {
                Text(model.setupCanComplete ? "Astra is ready to block distractions." : "Protection still needs attention.")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.55)
                    .multilineTextAlignment(.center)
                Text(readyDetail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }
            HStack(spacing: 9) {
                AstraStatusPill(title: "Local only", isReady: true)
                AstraStatusPill(title: "Protection", isReady: model.health.helperAvailable)
                AstraStatusPill(
                    title: "\(model.health.readyBrowserCount)/\(model.health.installedBrowserCount) browsers",
                    isReady: model.health.allInstalledBrowsersReady
                )
            }
        }
        .padding(44)
    }

    @ViewBuilder
    private var helperAction: some View {
        switch agent.status {
        case .enabled:
            if model.health.helperAvailable {
                AstraStatusPill(title: "Ready", isReady: true)
            } else {
                Button("Reset") {
                    Task {
                        await agent.unregister()
                        await model.refreshHealth()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(agent.isWorking)
            }
        case .notRegistered:
            Button("Enable") { enableAgent() }
                .buttonStyle(.borderedProminent)
                .tint(.astraAccent)
                .disabled(agent.isWorking)
        case .requiresApproval:
            Button("Open Settings") { agent.openLoginItemSettings() }
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
            return "Enabled in macOS; waiting for the helper to respond."
        }
        return agent.status.detail
    }

    private var readyDetail: String {
        if model.setupCanComplete {
            return "Your Deep Work routine blocks YouTube and Reddit for 45 minutes. You can add apps before the first session."
        }
        return "Return to Protection and finish the background helper and browser permissions. Astra will not pretend blocking works before they are ready."
    }

    private func trustPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.045), in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.075), lineWidth: 1) }
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(0...lastPage, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.astraAccent : .secondary.opacity(0.25))
                    .frame(width: index == page ? 20 : 6, height: 6)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: page)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup page \(page + 1) of \(lastPage + 1)")
    }

    private var primaryActionTitle: String {
        if page == lastPage { return "Open Astra" }
        if page == 1, !model.setupCanComplete { return "Finish setup above" }
        return "Continue"
    }

    private var primaryActionDisabled: Bool {
        page >= 1 && !model.setupCanComplete
    }

    private func performPrimaryAction() {
        if page == lastPage { model.completeOnboarding() }
        else { move(to: page + 1) }
    }

    private func move(to newPage: Int) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) { page = newPage }
    }

    private func enableAgent() {
        agent.register()
        Task { await model.waitForHelper() }
    }
}
