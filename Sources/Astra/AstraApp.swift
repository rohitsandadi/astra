import AppKit
import Darwin
import SwiftUI

@main
struct AstraApp: App {
    @NSApplicationDelegateAdaptor(AstraAppDelegate.self) private var appDelegate
    @StateObject private var model: AstraAppModel

    init() {
        _model = StateObject(wrappedValue: AstraAppModel(client: AstraClientFactory.makeDefault()))
    }

    var body: some Scene {
        WindowGroup("Astra", id: "main") {
            ZStack {
                AstraRootView(model: model)
                AstraWindowConfigurator()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            .frame(minWidth: 760, minHeight: 560)
            .preferredColorScheme(.dark)
        }
        .defaultSize(width: 960, height: 680)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Home") {
                    model.selectedDestination = .focus
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Routines") {
                    model.selectedDestination = .presets
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Settings") {
                    model.selectedDestination = .settings
                }
                .keyboardShortcut("3", modifiers: .command)
            }
        }

        MenuBarExtra {
            AstraMenuBarView(model: model)
        } label: {
            Label("Astra", systemImage: model.activeSession == nil ? "circle.dashed" : "circle.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            ZStack {
                AstraWindowBackground()
                AstraSettingsView(model: model)
                AstraWindowConfigurator()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            .frame(width: 720, height: 620)
            .tint(.astraAccent)
            .preferredColorScheme(.dark)
        }
    }
}

final class AstraAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--disable-protection") {
            Task { @MainActor in
                let agent = AstraAgentRegistrationService.shared
                await agent.unregister()
                Self.finishProtectionCommand(errorMessage: agent.errorMessage)
            }
            return
        }
        if CommandLine.arguments.contains("--enable-protection") {
            let agent = AstraAgentRegistrationService.shared
            agent.register()
            Self.finishProtectionCommand(errorMessage: agent.errorMessage)
        }
        if CommandLine.arguments.contains("--protection-status") {
            Task { @MainActor in
                do {
                    let health = try await AstraXPCEnforcerClient().health()
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    FileHandle.standardOutput.write(try encoder.encode(health))
                    FileHandle.standardOutput.write(Data("\n".utf8))
                    exit(EXIT_SUCCESS)
                } catch {
                    fputs("Astra: \(error.localizedDescription)\n", stderr)
                    exit(EXIT_FAILURE)
                }
            }
            return
        }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
    }

    private static func finishProtectionCommand(errorMessage: String?) -> Never {
        if let errorMessage {
            fputs("Astra: \(errorMessage)\n", stderr)
            exit(EXIT_FAILURE)
        }
        exit(EXIT_SUCCESS)
    }
}

struct AstraMenuBarView: View {
    @ObservedObject var model: AstraAppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                AstraBrandMark(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Astra").font(.headline)
                    Text(model.activeSession == nil ? "No active routine" : "Focus active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if let session = model.activeSession {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Focus")
                                .font(.body.weight(.medium))
                            Spacer()
                            Text(format(session.remaining(at: context.date)))
                                .font(.body.monospacedDigit().weight(.medium))
                        }
                        ProgressView(value: session.progress(at: context.date))
                            .tint(.astraAccent)
                        Text("Ends \(session.endsAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Open active session") {
                    showMainWindow(destination: .focus)
                }
                .astraPrimaryButton()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selectedPreset?.durationLabel ?? "Routine")
                        .font(.body.weight(.medium))
                    Text(model.selectedPreset?.routineSummary ?? "Create a routine to begin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Start Routine") {
                    showMainWindow(destination: .focus)
                }
                .astraPrimaryButton()
            }

            Divider()

            HStack {
                Button("Show Astra") { showMainWindow(destination: model.selectedDestination) }
                    .buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 300)
        .tint(.astraAccent)
    }

    private func showMainWindow(destination: AstraDestination) {
        model.selectedDestination = destination
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}
