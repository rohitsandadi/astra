import SwiftUI

struct AstraPresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AstraPreset
    var save: (AstraPreset) -> Void

    init(preset: AstraPreset, save: @escaping (AstraPreset) -> Void) {
        _draft = State(initialValue: preset)
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                AstraBrandMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit routine")
                        .font(.title2.weight(.semibold))
                    Text("Changes apply to future sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(draft.applications.count + draft.domains.count) targets")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(22)

            Divider()

            VStack(spacing: 18) {
                HStack(alignment: .bottom, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Name").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("Routine name", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Duration").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Stepper(
                            "\(draft.durationMinutes) min",
                            value: $draft.durationMinutes,
                            in: 5...1440,
                            step: 5
                        )
                        .fixedSize()
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Difficulty").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Picker("Difficulty", selection: $draft.difficulty) {
                            ForEach(AstraDifficulty.allCases, id: \.self) { difficulty in
                                Text(difficulty.title).tag(difficulty)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.032), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.075), lineWidth: 1)
                }

                AstraTargetPickerView(draft: $draft)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Text("Everything here stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save routine") { save(draft) }
                    .keyboardShortcut(.defaultAction)
                    .astraPrimaryButton()
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
            .background(.ultraThinMaterial)
        }
        .frame(width: 780, height: 700)
        .background(AstraWindowBackground())
        .preferredColorScheme(.dark)
    }
}
