import SwiftUI

struct AstraPresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AstraPreset
    var save: (AstraPreset) -> Void

    init(preset: AstraPreset, save: @escaping (AstraPreset) -> Void) {
        var initialDraft = preset
        initialDraft.name = Self.internalName(for: preset.id)
        _draft = State(initialValue: initialDraft)
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Routine")
                    .font(.title2.weight(.semibold))

                Spacer()

                Text(targetSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Selected targets: \(targetSummary)")
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider()

            VStack(spacing: 16) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Duration")
                                .font(.body.weight(.medium))
                            Spacer()
                            Stepper(
                                durationLabel,
                                value: $draft.durationMinutes,
                                in: 5...1440,
                                step: 5
                            )
                            .fixedSize()
                            .accessibilityLabel("Duration")
                            .accessibilityValue(durationLabel)
                        }

                        HStack(spacing: 7) {
                            ForEach([25, 45, 60, 90], id: \.self) { minutes in
                                AstraChoicePill(
                                    title: "\(minutes)",
                                    isSelected: draft.durationMinutes == minutes
                                ) {
                                    draft.durationMinutes = minutes
                                }
                                .accessibilityLabel("\(minutes) minutes")
                            }
                        }
                    }
                    .padding(14)

                    Divider().padding(.horizontal, 14)

                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 16) {
                            Text("Difficulty")
                                .font(.body.weight(.medium))
                            Spacer()
                            Picker("Difficulty", selection: $draft.difficulty) {
                                ForEach(AstraDifficulty.allCases, id: \.self) { difficulty in
                                    Text(difficulty.title).tag(difficulty)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 330)
                            .accessibilityLabel("Difficulty")
                        }

                        Text(draft.difficulty.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                }
                .background(Color.white.opacity(0.032), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.075), lineWidth: 1)
                }

                AstraTargetPickerView(draft: $draft)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") { saveDraft() }
                    .keyboardShortcut(.defaultAction)
                    .astraPrimaryButton()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
        .frame(
            minWidth: 600,
            idealWidth: 680,
            maxWidth: 760,
            minHeight: 500,
            idealHeight: 590,
            maxHeight: 700
        )
        .background(AstraWindowBackground())
        .preferredColorScheme(.dark)
    }

    private var targetSummary: String {
        "\(draft.applications.count) apps · \(draft.domains.count) websites"
    }

    private var durationLabel: String {
        let minutes = draft.durationMinutes
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    private func saveDraft() {
        var savedDraft = draft
        savedDraft.name = Self.internalName(for: draft.id)
        save(savedDraft)
    }

    private static func internalName(for id: UUID) -> String {
        "Routine \(id.uuidString.lowercased())"
    }
}
