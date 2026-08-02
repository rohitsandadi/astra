import SwiftUI

struct AstraPresetsView: View {
    @ObservedObject var model: AstraAppModel
    @State private var editingPreset: AstraPreset?
    @State private var createsPreset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraMetrics.pageSpacing) {
                HStack(alignment: .bottom) {
                    AstraPageHeader(
                        eyebrow: "Reusable focus",
                        title: "Routines",
                        detail: "Save a distraction boundary once, then start it in seconds."
                    )
                    Spacer()
                    Button("New routine", systemImage: "plus") {
                        createsPreset = true
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .controlSize(.large)
                    .astraPrimaryButton()
                }

                VStack(spacing: 0) {
                    ForEach(model.presets) { preset in
                        routineRow(preset)
                        if preset.id != model.presets.last?.id { Divider().padding(.leading, 62) }
                    }
                }
                .background(Color.white.opacity(0.032), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.085), lineWidth: 1)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(AstraMetrics.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $editingPreset) { preset in
            AstraPresetEditorView(preset: preset) { updated in
                model.upsert(updated)
                editingPreset = nil
            }
        }
        .sheet(isPresented: $createsPreset) {
            AstraPresetEditorView(
                preset: AstraPreset(name: "New Routine", durationMinutes: 45, difficulty: .commitment)
            ) { preset in
                model.upsert(preset)
                createsPreset = false
            }
        }
    }

    private func routineRow(_ preset: AstraPreset) -> some View {
        HStack(spacing: 14) {
            Image(systemName: preset.difficulty.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(model.selectedPresetID == preset.id ? Color.astraAccent : .secondary)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.headline)
                Text("\(durationLabel(preset.durationMinutes)) · \(preset.difficulty.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Label("\(preset.applications.count)", systemImage: "app.dashed")
                Label("\(preset.domains.count)", systemImage: "globe")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if model.selectedPresetID == preset.id {
                AstraStatusPill(title: "Current", isReady: true)
            } else {
                Button("Use") { model.selectPreset(preset.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Menu {
                Button("Edit", systemImage: "pencil") { editingPreset = preset }
                Button("Use and focus", systemImage: "circle.dashed") {
                    model.selectPreset(preset.id)
                    model.selectedDestination = .focus
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    model.deletePreset(preset)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Actions for \(preset.name)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editingPreset = preset }
        .contextMenu {
            Button("Edit") { editingPreset = preset }
            Button("Use for focus") {
                model.selectPreset(preset.id)
                model.selectedDestination = .focus
            }
        }
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }
}
