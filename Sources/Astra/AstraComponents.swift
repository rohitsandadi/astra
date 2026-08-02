import AppKit
import SwiftUI

struct AstraPageHeader: View {
    var eyebrow: String?
    var title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AstraMetrics.compactSpacing) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.35)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .default))
                .tracking(-0.8)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AstraSectionHeading: View {
    var eyebrow: String?
    var title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.25)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.title3.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AstraStatusPill: View {
    var title: String
    var isReady: Bool

    var body: some View {
        Label(title, systemImage: isReady ? "checkmark.circle.fill" : "circle.dashed")
            .font(.caption.weight(.medium))
            .foregroundStyle(isReady ? Color.astraAccent : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.075), lineWidth: 1) }
            .accessibilityLabel("\(title), \(isReady ? "ready" : "attention needed")")
    }
}

struct AstraStatusBanner: View {
    var title: String
    var detail: String
    var isReady: Bool
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isReady ? "checkmark.shield.fill" : "exclamationmark.shield")
                .font(.body.weight(.semibold))
                .foregroundStyle(isReady ? Color.astraAccent : .secondary)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .astraSurface(cornerRadius: AstraMetrics.compactCornerRadius, emphasized: !isReady, padding: 12)
    }
}

struct AstraEmptyState: View {
    var systemImage: String
    var title: String
    var detail: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(detail)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct AstraAppIcon: View {
    var application: AstraBlockedApplication
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: application.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct AstraBrowserIcon: View {
    var browser: AstraBrowser
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct AstraBrowserRow: View {
    var permission: AstraBrowserPermission
    var helperReady: Bool = true
    var isBusy: Bool
    var requestPermission: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AstraBrowserIcon(browser: permission.browser, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.browser.displayName)
                    .font(.body.weight(.medium))
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            switch permission.status {
            case .notRequested, .denied:
                Button(permission.status == .denied ? "Try again" : "Allow") {
                    requestPermission()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy || !helperReady)
                .help(helperReady ? "macOS will ask for browser access." : "Enable app blocking first.")
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.astraAccent)
            case .notInstalled:
                Text("Not installed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private var statusDetail: String {
        if !helperReady, permission.status != .notInstalled {
            return "Enable app blocking first."
        }
        return switch permission.status {
        case .ready: "Ready"
        case .notRequested, .denied: "Browser access needed"
        case .notInstalled: "Not installed"
        }
    }
}

struct AstraChoicePill: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.astraAccent : Color.white.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected ? Color.astraAccent : Color.white.opacity(0.075),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct AstraBrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: appIcon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "Astra", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApplication.shared.applicationIconImage
    }
}

struct AstraFloatingNavigation: View {
    @Binding var selection: AstraDestination

    var body: some View {
        HStack(spacing: AstraMetrics.space1) {
            ForEach(AstraDestination.allCases) { destination in
                Button {
                    selection = destination
                } label: {
                    Image(systemName: destination.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == destination ? Color.astraAccent : .secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            selection == destination ? Color.astraAccent.opacity(0.16) : Color.clear,
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(destination.title)
                .accessibilityLabel(destination.title)
                .accessibilityAddTraits(selection == destination ? .isSelected : [])
            }
        }
        .astraGlassChrome(cornerRadius: AstraMetrics.floatingCornerRadius, padding: AstraMetrics.space1)
    }
}

struct AstraRoutineRow: View {
    var preset: AstraPreset
    var actionTitle: String = "Start"
    var actionSystemImage: String = "play.fill"
    var action: () -> Void
    var edit: (() -> Void)?
    var delete: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AstraMetrics.space2) {
            Button(action: action) {
                HStack(spacing: AstraMetrics.space3) {
                    Image(systemName: preset.difficulty.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.astraAccent)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.durationLabel)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(preset.routineSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: AstraMetrics.space3)

                    targetIcons

                    Label(actionTitle, systemImage: actionSystemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.astraAccent)
                        .padding(.leading, AstraMetrics.space2)
                }
                .padding(.horizontal, AstraMetrics.space2)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .background(
                    Color.white.opacity(isHovering ? 0.055 : 0),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .accessibilityLabel(preset.routineAccessibilityLabel)
            .accessibilityHint("\(actionTitle) this routine")

            if edit != nil || delete != nil {
                Menu {
                    if let edit {
                        Button("Edit", systemImage: "pencil", action: edit)
                    }
                    if let delete {
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel("Actions for \(preset.routineAccessibilityLabel)")
                .padding(.trailing, AstraMetrics.space2)
            }
        }
        .frame(minHeight: 58)
    }

    @ViewBuilder
    private var targetIcons: some View {
        if !preset.applications.isEmpty {
            HStack(spacing: -5) {
                ForEach(Array(preset.applications.prefix(3))) { application in
                    AstraAppIcon(application: application, size: 22)
                        .padding(2)
                        .background(Color.astraCanvas, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .accessibilityHidden(true)
        } else if !preset.domains.isEmpty {
            Image(systemName: "globe")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 26)
                .accessibilityHidden(true)
        }
    }
}
