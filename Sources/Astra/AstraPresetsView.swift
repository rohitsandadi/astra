import SwiftUI

struct AstraPresetsView: View {
    @ObservedObject var model: AstraAppModel
    @State private var editingPreset: AstraPreset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraMetrics.space4) {
                HStack {
                    Text("Routines")
                        .font(.system(size: 30, weight: .semibold))
                        .tracking(-0.5)
                    Spacer()
                    Button("New Routine", systemImage: "plus") {
                        editingPreset = makeNewRoutine()
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .controlSize(.large)
                    .astraPrimaryButton()
                }

                VStack(spacing: 0) {
                    ForEach(model.presets) { preset in
                        AstraRoutineRow(
                            preset: preset,
                            actionTitle: "Edit",
                            actionSystemImage: "chevron.right",
                            action: { editingPreset = preset },
                            delete: model.presets.count > 1 ? { model.deletePreset(preset) } : nil
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
            .frame(maxWidth: AstraMetrics.contentWidth, alignment: .leading)
            .padding(AstraMetrics.pagePadding)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .sheet(item: $editingPreset) { preset in
            AstraPresetEditorView(preset: preset) { updated in
                model.upsert(updated)
                editingPreset = nil
            }
        }
    }

    private func makeNewRoutine() -> AstraPreset {
        AstraPreset(
            name: "Routine \(UUID().uuidString.lowercased())",
            durationMinutes: 45,
            difficulty: .commitment
        )
    }
}
