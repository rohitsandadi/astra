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
                Button(permission.status == .denied ? "Try again" : "Open & allow") {
                    requestPermission()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy || !helperReady)
                .help(helperReady ? "macOS will ask for Automation access." : "Enable Protection first.")
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
        .accessibilityElement(children: .combine)
    }

    private var statusDetail: String {
        if !helperReady, permission.status != .notInstalled {
            return "Enable Protection before requesting access."
        }
        if let detail = permission.detail, !detail.isEmpty { return detail }
        return permission.status.title
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
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(Color.black)
            Ellipse()
                .trim(from: 0.05, to: 0.76)
                .stroke(
                    Color.white.opacity(0.94),
                    style: StrokeStyle(lineWidth: max(1.5, size * 0.105), lineCap: .round)
                )
                .frame(width: size * 0.61, height: size * 0.53)
                .rotationEffect(.degrees(-29))
                .offset(y: size * 0.015)
            Ellipse()
                .trim(from: 0.34, to: 0.95)
                .stroke(
                    Color.astraAccent,
                    style: StrokeStyle(lineWidth: max(1, size * 0.055), lineCap: .round)
                )
                .frame(width: size * 0.59, height: size * 0.49)
                .rotationEffect(.degrees(151))
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 0.75)
        }
        .accessibilityHidden(true)
    }
}
