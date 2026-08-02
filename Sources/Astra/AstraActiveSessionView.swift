import SwiftUI

struct AstraActiveSessionView: View {
    @ObservedObject var model: AstraAppModel
    var session: AstraFocusSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var interruptionAction: InterruptionAction?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 20) {
                        sessionHeader(at: context.date)
                        orbitalTimer(at: context.date)
                        intention
                        enforcementIssues
                        sessionDetails(at: context.date)
                        controls(at: context.date)
                    }
                }
            }
            .frame(maxWidth: 720)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $interruptionAction, onDismiss: {
            Task { await model.cancelInterruption() }
        }) { action in
            AstraInterruptionView(model: model, action: action)
        }
    }

    private func sessionHeader(at date: Date) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.preset.name.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.astraAccent)
                Text(isOnBreak(at: date) ? "A quiet pause." : "Focus is protected.")
                    .font(.title.weight(.semibold))
            }
            Spacer()
            AstraStatusPill(
                title: isOnBreak(at: date) ? "Break" : session.difficulty.title,
                isReady: true
            )
        }
    }

    private func orbitalTimer(at date: Date) -> some View {
        let displayInterval = session.breakRemaining(at: date) ?? session.remaining(at: date)
        let progress = session.progress(at: date)

        return ZStack {
            Circle()
                .stroke(.primary.opacity(0.1), lineWidth: 9)
                .frame(width: 244, height: 244)
            Circle()
                .trim(from: 0, to: max(progress, 0.002))
                .stroke(
                    Color.astraAccent,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .frame(width: 244, height: 244)
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)

            VStack(spacing: 8) {
                Text(format(displayInterval))
                    .font(.system(size: 48, weight: .medium, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(isOnBreak(at: date) ? "BREAK REMAINING" : "REMAINING")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Text("Ends \(session.endsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOnBreak(at: date) ? "Break timer" : "Focus timer")
        .accessibilityValue("\(accessibilityDuration(displayInterval)) remaining, ending at \(session.endsAt.formatted(date: .omitted, time: .shortened))")
    }

    @ViewBuilder
    private var intention: some View {
        if let intention = session.intention, !intention.isEmpty {
            VStack(spacing: 7) {
                Text("RIGHT NOW")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text(intention)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 560)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var enforcementIssues: some View {
        if !session.enforcementHealth.issues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Some website blocking needs attention", systemImage: "exclamationmark.shield")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.astraAccent)
                ForEach(session.enforcementHealth.issues, id: \.self) { issue in
                    Text(issue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Review browser access") {
                    model.selectedDestination = .settings
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .astraSurface(cornerRadius: AstraMetrics.compactCornerRadius, emphasized: true, padding: 12)
        }
    }

    private func sessionDetails(at date: Date) -> some View {
        HStack(spacing: 24) {
            detailItem(
                systemImage: "app.dashed",
                value: "\(session.preset.applications.count)",
                label: "Apps"
            )
            Divider().frame(height: 32)
            detailItem(
                systemImage: "globe",
                value: "\(session.preset.domains.count)",
                label: "Websites"
            )
            Divider().frame(height: 32)
            detailItem(
                systemImage: session.difficulty.systemImage,
                value: session.difficulty.title,
                label: "Boundary"
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.035), in: Capsule())
        .overlay { Capsule().stroke(Color.white.opacity(0.075), lineWidth: 1) }
    }

    private func detailItem(systemImage: String, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.astraAccent)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.callout.weight(.medium))
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func controls(at date: Date) -> some View {
        if isOnBreak(at: date) {
            Text("Your original end time stays the same. Focus resumes automatically when this break ends.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if session.difficulty == .locked {
            Label("This session is locked until its end time.", systemImage: "lock.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.primary.opacity(0.04), in: Capsule())
        } else {
            HStack(spacing: 10) {
                Button("Take a break", systemImage: "cup.and.saucer") {
                    interruptionAction = .breakSession
                }
                .controlSize(.large)
                .astraSecondaryButton()

                Button("End early") {
                    interruptionAction = .endSession
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .astraGlassChrome(cornerRadius: 18, padding: 10)
        }
    }

    private func isOnBreak(at date: Date) -> Bool {
        (session.breakRemaining(at: date) ?? 0) > 0
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

    private func accessibilityDuration(_ interval: TimeInterval) -> String {
        Duration.seconds(max(0, interval)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

enum InterruptionAction: String, Identifiable {
    case breakSession
    case endSession

    var id: Self { self }
}

struct AstraInterruptionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AstraAppModel
    var action: InterruptionAction
    @State private var breakMinutes = 5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: action == .breakSession ? "cup.and.saucer" : "arrow.uturn.backward")
                    .font(.largeTitle)
                    .foregroundStyle(Color.astraAccent)

                if let challenge = model.interruptionChallenge {
                    countdown(challenge, at: context.date)
                } else {
                    choice
                }
            }
            .padding(28)
            .frame(width: 460)
        }
    }

    private var choice: some View {
        VStack(alignment: .leading, spacing: 18) {
            AstraSectionHeading(
                eyebrow: "Honor the pause",
                title: action == .breakSession ? "Take a short break?" : "End this session early?",
                detail: waitExplanation
            )

            if action == .breakSession {
                HStack {
                    Text("Break length")
                    Spacer()
                    Stepper("\(breakMinutes) minutes", value: $breakMinutes, in: 1...15)
                        .fixedSize()
                }
                Text("The break will not move your session's original end time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Stay focused") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action == .breakSession ? "Begin pause" : "Begin countdown") {
                    Task {
                        let kind: AstraInterruptionKind = action == .breakSession
                            ? .breakFor(minutes: breakMinutes)
                            : .endSession
                        await model.beginInterruption(kind)
                    }
                }
                .astraPrimaryButton()
                .disabled(model.isBusy)
            }
        }
    }

    private func countdown(_ challenge: AstraInterruptionChallenge, at date: Date) -> some View {
        let remaining = max(0, Int(challenge.readyAt.timeIntervalSince(date).rounded(.up)))

        return VStack(alignment: .leading, spacing: 20) {
            AstraSectionHeading(
                eyebrow: "A deliberate choice",
                title: remaining > 0 ? "Stay with the decision." : "The pause is complete.",
                detail: remaining > 0
                    ? "You can return to focus at any time. Keep this window open to finish the interruption."
                    : "You may now confirm, or return to your session."
            )

            Text(timeLabel(remaining))
                .font(.system(size: 44, weight: .medium, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("\(remaining) seconds remaining")

            HStack {
                Button("Return to focus") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action == .breakSession ? "Take break" : "End session") {
                    Task {
                        if await model.commitInterruption() {
                            dismiss()
                        }
                    }
                }
                .astraPrimaryButton()
                .disabled(remaining > 0 || model.isBusy)
            }
        }
    }

    private var waitExplanation: String {
        guard let difficulty = model.activeSession?.difficulty else { return "" }
        return switch difficulty {
        case .flexible:
            "A six-second pause keeps the action intentional."
        case .commitment:
            "A commitment countdown must finish before this action becomes available. Repeated interruptions take longer."
        case .locked:
            "Locked sessions cannot be interrupted."
        }
    }

    private func timeLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}
