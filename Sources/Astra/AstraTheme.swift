import AppKit
import SwiftUI

extension Color {
    /// Astra's only non-semantic color. Everything else is neutral or supplied
    /// by macOS so the interface remains restrained and accessible.
    static let astraAccent = Color(
        .sRGB,
        red: 102.0 / 255.0,
        green: 105.0 / 255.0,
        blue: 183.0 / 255.0,
        opacity: 1
    )

    static let astraCanvas = Color(
        .sRGB,
        red: 10.0 / 255.0,
        green: 10.0 / 255.0,
        blue: 11.0 / 255.0,
        opacity: 1
    )
}

enum AstraMetrics {
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32

    static let compactSpacing = space2
    static let controlSpacing = space3
    static let sectionSpacing = space4
    static let pageSpacing = space6
    static let cornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 12
    static let floatingCornerRadius: CGFloat = 18
    static let pagePadding = space6
    static let contentWidth: CGFloat = 820
    static let topBarHeight: CGFloat = 54
    static let navigationClearance: CGFloat = 68
}

/// A quiet content-layer surface. Liquid Glass belongs to navigation and
/// controls; using it behind ordinary content destroys hierarchy.
struct AstraContentSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var cornerRadius: CGFloat
    var emphasized: Bool
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                reduceTransparency
                    ? Color(nsColor: .controlBackgroundColor)
                    : Color.white.opacity(emphasized ? 0.065 : 0.038),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        emphasized
                            ? Color.astraAccent.opacity(contrast == .increased ? 0.7 : 0.38)
                            : Color.white.opacity(contrast == .increased ? 0.24 : 0.085),
                        lineWidth: emphasized ? 1.25 : 1
                    )
            }
    }
}

/// A floating functional layer used sparingly for sticky controls and chrome.
struct AstraGlassChromeModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat
    var padding: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content
                .padding(padding)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .padding(padding)
                .background(
                    reduceTransparency
                        ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                        : AnyShapeStyle(.ultraThinMaterial),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.11), lineWidth: 1)
                }
        }
    }
}

extension View {
    func astraSurface(
        cornerRadius: CGFloat = AstraMetrics.cornerRadius,
        emphasized: Bool = false,
        padding: CGFloat = 16
    ) -> some View {
        modifier(
            AstraContentSurfaceModifier(
                cornerRadius: cornerRadius,
                emphasized: emphasized,
                padding: padding
            )
        )
    }

    func astraGlassChrome(
        cornerRadius: CGFloat = AstraMetrics.floatingCornerRadius,
        padding: CGFloat = 14
    ) -> some View {
        modifier(AstraGlassChromeModifier(cornerRadius: cornerRadius, padding: padding))
    }

    @ViewBuilder
    func astraPrimaryButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
                .tint(.astraAccent)
        } else {
            buttonStyle(.borderedProminent)
                .tint(.astraAccent)
        }
    }

    @ViewBuilder
    func astraSecondaryButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
                .tint(Color.white.opacity(0.14))
        } else {
            buttonStyle(.bordered)
                .tint(Color(nsColor: .secondaryLabelColor))
        }
    }
}

struct AstraWindowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color.astraCanvas
            } else {
                AstraVisualEffectBackground()
                Color.black.opacity(0.78)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.035),
                        Color.clear,
                        Color.astraAccent.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// One window-level material keeps Astra translucent without stacking blur on
/// every row and card. The active state preserves the same contrast when the
/// window is not key.
private struct AstraVisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
    }
}

/// Gives hidden-titlebar SwiftUI windows real translucency instead of drawing
/// an opaque rectangle behind material views.
struct AstraWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
    }
}
