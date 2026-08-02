import SwiftUI

struct AstraRootView: View {
    @ObservedObject var model: AstraAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AstraWindowBackground()

            VStack(spacing: 0) {
                topBar
                destination
                    .id(model.selectedDestination)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, model.activeSession == nil ? AstraMetrics.navigationClearance : 0)
            }

            if model.activeSession == nil {
                AstraFloatingNavigation(selection: $model.selectedDestination)
                    .padding(AstraMetrics.space4)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .tint(.astraAccent)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.selectedDestination)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.activeSession?.id)
        .sheet(isPresented: $model.showsOnboarding) {
            AstraOnboardingView(model: model)
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

    private var topBar: some View {
        HStack(spacing: AstraMetrics.space2) {
            AstraBrandMark(size: 30)
            Text("Astra")
                .font(.headline.weight(.semibold))
            Spacer()
            if model.activeSession != nil, model.selectedDestination != .focus {
                Button("Back to Focus", systemImage: "timer") {
                    model.selectedDestination = .focus
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.leading, 78)
        .padding(.trailing, AstraMetrics.space6)
        .frame(height: AstraMetrics.topBarHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
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
}
