import SwiftUI

struct AstraRootView: View {
    @ObservedObject var model: AstraAppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 188, ideal: 214, max: 244)
        } detail: {
            ZStack {
                AstraWindowBackground()
                destination
                    .id(model.selectedDestination)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.astraAccent)
        .sheet(isPresented: $model.showsOnboarding) {
            AstraOnboardingView(model: model)
                .interactiveDismissDisabled()
        }
        .alert(
            "Astra needs your attention",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .task { await model.bootstrap() }
        .task(id: model.activeSession?.id) {
            while !Task.isCancelled, model.activeSession != nil {
                try? await Task.sleep(for: .seconds(2))
                await model.refreshSessionFromClient()
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                AstraBrandMark(size: 34)
                Text("Astra")
                    .font(.headline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 16)

            List(selection: $model.selectedDestination) {
                Section {
                    ForEach(AstraDestination.allCases) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(destination)
                            .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(spacing: 10) {
                if let session = model.activeSession {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Label("Focus active", systemImage: "circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.astraAccent)
                                Spacer()
                                Text(shortTime(session.remaining(at: context.date)))
                                    .font(.caption.monospacedDigit().weight(.medium))
                            }
                            ProgressView(value: session.progress(at: context.date))
                                .progressViewStyle(.linear)
                                .tint(.astraAccent)
                            Text(session.preset.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Button {
                        model.selectedDestination = .settings
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: model.selectionIsReady ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                                .foregroundStyle(model.selectionIsReady ? Color.astraAccent : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.readinessTitle)
                                    .font(.caption.weight(.semibold))
                                Text(model.selectionIsReady ? "Astra can hold this focus." : "Review protection setup.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.black.opacity(0.2))
            .overlay(alignment: .top) { Divider() }
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var destination: some View {
        switch model.selectedDestination {
        case .focus:
            if let session = model.activeSession {
                AstraActiveSessionView(model: model, session: session)
            } else {
                AstraFocusComposerView(model: model)
            }
        case .presets:
            AstraPresetsView(model: model)
        case .settings:
            AstraSettingsView(model: model)
        }
    }

    private func shortTime(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
