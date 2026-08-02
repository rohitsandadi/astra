import SwiftUI

/// Astra's home screen is deliberately a launcher, not a configuration form.
/// Routine details live in the editor and the home surface stays scannable.
struct AstraFocusComposerView: View {
    @ObservedObject var model: AstraAppModel
    @State private var showsRoutineLauncher = false
    @State private var creatingPreset: AstraPreset?
    @State private var confirmingPreset: AstraPreset?
    @State private var launcherFollowUp: LauncherFollowUp?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraMetrics.space4) {
                header

                if model.selectionRequiresProtection, !model.selectionIsReady {
                    setupNotice
                }

                routineList
            }
            .frame(maxWidth: AstraMetrics.contentWidth, alignment: .leading)
            .padding(AstraMetrics.pagePadding)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .sheet(isPresented: $showsRoutineLauncher, onDismiss: handleLauncherDismissal) {
            AstraRoutineLauncherView(
                presets: model.presets,
                start: { preset in
                    launcherFollowUp = .start(preset)
                    showsRoutineLauncher = false
                },
                create: {
                    launcherFollowUp = .create
                    showsRoutineLauncher = false
                }
            )
        }
        .sheet(item: $creatingPreset) { draft in
            AstraPresetEditorView(preset: draft) { preset in
                model.upsert(preset)
                creatingPreset = nil
            }
        }
        .sheet(item: $confirmingPreset) { preset in
            AstraRoutineConfirmationView(
                preset: preset,
                runningApplications: model.runningBlockedApplications,
                isBusy: model.isBusy,
                cancel: { confirmingPreset = nil },
                start: {
                    confirmingPreset = nil
                    Task { await model.startFocus() }
                }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AstraMetrics.space3) {
            Text("Routines")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.5)

            Spacer()

            Button("New", systemImage: "plus") {
                creatingPreset = makeNewRoutine()
            }
            .keyboardShortcut("n", modifiers: .command)
            .controlSize(.large)
            .astraSecondaryButton()

            Button("Start Routine", systemImage: "play.fill") {
                showsRoutineLauncher = true
            }
            .keyboardShortcut(.return, modifiers: .command)
            .controlSize(.large)
            .astraPrimaryButton()
        }
    }

    private var setupNotice: some View {
        HStack(spacing: AstraMetrics.space3) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(Color.astraAccent)
            Text("Astra needs a quick setup.")
                .font(.callout.weight(.medium))
            Spacer()
            Button("Set Up") { model.reopenOnboarding() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .astraSurface(cornerRadius: AstraMetrics.compactCornerRadius, emphasized: true, padding: 12)
    }

    private var routineList: some View {
        VStack(spacing: 0) {
            ForEach(model.presets) { preset in
                AstraRoutineRow(
                    preset: preset,
                    action: { requestStart(preset) }
                )

                if preset.id != model.presets.last?.id {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func makeNewRoutine() -> AstraPreset {
        AstraPreset(
            name: "Routine \(UUID().uuidString.lowercased())",
            durationMinutes: 45,
            difficulty: .commitment
        )
    }

    private func requestStart(_ preset: AstraPreset) {
        guard !model.isBusy else { return }
        model.selectPreset(preset.id)

        guard model.selectionIsReady else {
            model.reopenOnboarding()
            return
        }

        if preset.difficulty == .locked || !model.runningBlockedApplications.isEmpty {
            confirmingPreset = preset
        } else {
            Task { await model.startFocus() }
        }
    }

    private func handleLauncherDismissal() {
        let followUp = launcherFollowUp
        launcherFollowUp = nil
        switch followUp {
        case .start(let preset):
            requestStart(preset)
        case .create:
            creatingPreset = makeNewRoutine()
        case nil:
            break
        }
    }
}

private enum LauncherFollowUp {
    case start(AstraPreset)
    case create
}

private struct AstraRoutineLauncherView: View {
    @Environment(\.dismiss) private var dismiss
    var presets: [AstraPreset]
    var start: (AstraPreset) -> Void
    var create: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Start Routine")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(presets) { preset in
                        AstraRoutineRow(preset: preset) { start(preset) }
                        if preset.id != presets.last?.id {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)) }
                .padding(16)
            }

            Divider()

            Button("New Routine", systemImage: "plus", action: create)
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .foregroundStyle(Color.astraAccent)
        }
        .frame(width: 480)
        .frame(minHeight: 260, idealHeight: 420, maxHeight: 560)
        .background(AstraWindowBackground())
        .preferredColorScheme(.dark)
    }
}

private struct AstraRoutineConfirmationView: View {
    var preset: AstraPreset
    var runningApplications: [AstraBlockedApplication]
    var isBusy: Bool
    var cancel: () -> Void
    var start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                AstraBrandMark(size: 36)
                Text(preset.difficulty == .locked ? "Lock this routine?" : "Close blocked apps?")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            if preset.difficulty == .locked {
                Text("You won't be able to take a break or end this \(preset.durationLabel) routine early.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !runningApplications.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Save your work first. Astra will close:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(runningApplications) { application in
                        HStack(spacing: 10) {
                            AstraAppIcon(application: application, size: 26)
                            Text(application.displayName)
                        }
                    }
                }
                .astraSurface(cornerRadius: 12, padding: 12)
            }

            HStack {
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(preset.difficulty == .locked ? "Lock & Start" : "Start Routine", action: start)
                    .keyboardShortcut(.defaultAction)
                    .astraPrimaryButton()
                    .disabled(isBusy)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(AstraWindowBackground())
        .preferredColorScheme(.dark)
    }
}
