import SwiftUI

struct AstraFocusComposerView: View {
    @ObservedObject var model: AstraAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsStartConfirmation = false
    @State private var showsCustomDuration = false
    @State private var editingPreset: AstraPreset?

    private let durationShortcuts = [25, 45, 60, 90]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraMetrics.pageSpacing) {
                header
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        composer
                            .frame(minWidth: 460, maxWidth: .infinity)
                        focusSummary
                            .frame(width: 252)
                    }
                    VStack(spacing: 18) {
                        composer
                        focusSummary
                    }
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(AstraMetrics.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showsStartConfirmation) { startConfirmation }
        .sheet(item: $editingPreset) { preset in
            AstraPresetEditorView(preset: preset) { updated in
                model.upsert(updated)
                editingPreset = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            AstraPageHeader(
                eyebrow: "Focus now",
                title: "Make room for what matters.",
                detail: "Choose what stays out, then let Astra hold the line locally."
            )
            Spacer()
            if let preset = model.selectedPreset {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("ROUTINE")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Picker("Routine", selection: Binding(
                        get: { model.selectedPresetID },
                        set: { model.selectPreset($0) }
                    )) {
                        ForEach(model.presets) { option in
                            Text(option.name).tag(Optional(option.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .accessibilityLabel("Focus routine, currently \(preset.name)")
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Text("What will you work on?")
                    .font(.headline)
                TextField("Write the next clear outcome…", text: $model.intention)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    }
                    .accessibilityHint("This intention appears during your session and on blocked pages.")
            }
            .padding(20)

            Divider().padding(.horizontal, 20)

            durationSection
                .padding(20)

            Divider().padding(.horizontal, 20)

            boundarySection
                .padding(20)

            Divider().padding(.horizontal, 20)

            difficultySection
                .padding(20)
        }
        .background(Color.white.opacity(0.032), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.085), lineWidth: 1)
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("Duration").font(.headline)
                Spacer()
                Text(durationLabel)
                    .font(.title2.monospacedDigit().weight(.medium))
                    .contentTransition(.numericText())
            }

            HStack(spacing: 7) {
                ForEach(durationShortcuts, id: \.self) { minutes in
                    AstraChoicePill(title: "\(minutes)", isSelected: model.durationMinutes == minutes) {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                            model.durationMinutes = minutes
                            showsCustomDuration = false
                        }
                    }
                }
                AstraChoicePill(
                    title: "Custom",
                    isSelected: showsCustomDuration || !durationShortcuts.contains(model.durationMinutes)
                ) {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        showsCustomDuration.toggle()
                    }
                }
            }

            if showsCustomDuration || !durationShortcuts.contains(model.durationMinutes) {
                HStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { Double(model.durationMinutes) },
                            set: { model.durationMinutes = Int($0.rounded() / 5) * 5 }
                        ),
                        in: 5...240,
                        step: 5
                    )
                    .tint(.astraAccent)
                    Stepper(
                        "\(model.durationMinutes) minutes",
                        value: $model.durationMinutes,
                        in: 5...1440,
                        step: 5
                    )
                    .labelsHidden()
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var boundarySection: some View {
        Button {
            editingPreset = model.selectedPreset
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.astraAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Apps & websites")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let preset = model.selectedPreset {
                        Text(targetSummary(preset))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                if let preset = model.selectedPreset, !preset.applications.isEmpty {
                    HStack(spacing: -5) {
                        ForEach(Array(preset.applications.prefix(4))) { application in
                            AstraAppIcon(application: application, size: 24)
                                .padding(2)
                                .background(Color.astraCanvas, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                Text("Edit")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.astraAccent)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose the applications and website domains Astra will block.")
    }

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Difficulty").font(.headline)
                Spacer()
                Image(systemName: model.difficulty.systemImage)
                    .foregroundStyle(Color.astraAccent)
            }
            HStack(spacing: 7) {
                ForEach(AstraDifficulty.allCases, id: \.self) { difficulty in
                    AstraChoicePill(
                        title: difficulty.title,
                        isSelected: model.difficulty == difficulty
                    ) {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                            model.difficulty = difficulty
                        }
                    }
                }
            }
            Text(model.difficulty.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var focusSummary: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Ready to focus")
                        .font(.headline)
                    Spacer()
                    Image(systemName: model.selectionIsReady ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                        .foregroundStyle(model.selectionIsReady ? Color.astraAccent : .secondary)
                }

                readinessRow("Protection", value: model.readinessTitle, ready: model.selectionIsReady)
                if let preset = model.selectedPreset {
                    readinessRow("Routine", value: preset.name, ready: true)
                    readinessRow("Ends", value: endTime, ready: true)
                }

                if let blocker = model.startBlockerReason {
                    Text(blocker)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Complete setup") {
                        model.selectedDestination = .settings
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .astraSurface(cornerRadius: 16, emphasized: !model.selectionIsReady, padding: 16)

            VStack(alignment: .leading, spacing: 12) {
                Text(model.intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "A clear block of time."
                     : model.intention)
                    .font(.callout.weight(.medium))
                    .lineLimit(3)
                    .foregroundStyle(model.intention.isEmpty ? .secondary : .primary)

                Button {
                    if needsStartConfirmation {
                        showsStartConfirmation = true
                    } else {
                        Task { await model.startFocus() }
                    }
                } label: {
                    HStack {
                        if model.isBusy { ProgressView().controlSize(.small) }
                        Text("Begin \(durationLabel) focus")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .controlSize(.large)
                .astraPrimaryButton()
                .disabled(!model.canStartFocus || model.isBusy)
            }
            .astraGlassChrome(cornerRadius: 18, padding: 14)
        }
    }

    private func readinessRow(_ title: String, value: String, ready: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .foregroundStyle(ready ? .primary : .secondary)
        }
    }

    private var startConfirmation: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                AstraBrandMark(size: 42)
                Spacer()
                AstraStatusPill(title: model.difficulty.title, isReady: true)
            }

            AstraSectionHeading(
                eyebrow: model.difficulty == .locked ? "Final confirmation" : "Before focus begins",
                title: model.difficulty == .locked ? "Lock this session?" : "Ready to begin?",
                detail: confirmationDetail
            )

            if !model.runningBlockedApplications.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SAVE WORK IN THESE APPS")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text("Astra will ask them to close, then keep them closed until focus ends.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(model.runningBlockedApplications) { application in
                        HStack(spacing: 9) {
                            AstraAppIcon(application: application)
                            Text(application.displayName)
                        }
                    }
                }
                .astraSurface(cornerRadius: 12, padding: 14)
            }

            HStack {
                Button("Go back") { showsStartConfirmation = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.difficulty == .locked ? "Lock and begin" : "Begin focus") {
                    showsStartConfirmation = false
                    Task { await model.startFocus() }
                }
                .keyboardShortcut(.defaultAction)
                .astraPrimaryButton()
            }
        }
        .padding(28)
        .frame(width: 470)
        .background(AstraWindowBackground())
        .preferredColorScheme(.dark)
    }

    private var needsStartConfirmation: Bool {
        model.difficulty == .locked || !model.runningBlockedApplications.isEmpty
    }

    private var confirmationDetail: String {
        if model.difficulty == .locked {
            return "For \(durationLabel), Astra will offer no breaks or early ending. Quitting the window does not stop Protection."
        }
        return "Astra will hold the selected apps and websites until \(endTime)."
    }

    private func targetSummary(_ preset: AstraPreset) -> String {
        let apps = "\(preset.applications.count) \(preset.applications.count == 1 ? "app" : "apps")"
        let sites = "\(preset.domains.count) \(preset.domains.count == 1 ? "website" : "websites")"
        if preset.applications.isEmpty && preset.domains.isEmpty { return "Timer only — choose what to block" }
        return "\(apps) · \(sites)"
    }

    private var endTime: String {
        Date.now.addingTimeInterval(TimeInterval(model.durationMinutes * 60))
            .formatted(date: .omitted, time: .shortened)
    }

    private var durationLabel: String {
        if model.durationMinutes < 60 { return "\(model.durationMinutes) min" }
        let hours = model.durationMinutes / 60
        let minutes = model.durationMinutes % 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }
}
