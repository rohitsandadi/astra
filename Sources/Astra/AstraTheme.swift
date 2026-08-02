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
    static let compactSpacing: CGFloat = 6
    static let controlSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 16
    static let pageSpacing: CGFloat = 24
    static let cornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 12
    static let floatingCornerRadius: CGFloat = 20
    static let pagePadding: CGFloat = 28
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
        } else {
            buttonStyle(.bordered)
        }
    }
}

struct AstraWindowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color.astraCanvas
            if !reduceTransparency {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.025),
                        Color.clear,
                        Color.astraAccent.opacity(0.025)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
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
