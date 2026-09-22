import SwiftUI

/// Warm paper and ink theme shared by the app surfaces.
enum Theme {

    static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { $0.name == .darkAqua || $0.name == .vibrantDark || $0.name == .accessibilityHighContrastDarkAqua || $0.name == .accessibilityHighContrastVibrantDark ? dark : light }))
    }

    /// Panel background — neutral ivory (light) / neutral graphite (dark).
    static let paper = dynamic(
        NSColor(calibratedRed: 0.965, green: 0.966, blue: 0.972, alpha: 0.97),
        NSColor(calibratedRed: 0.115, green: 0.120, blue: 0.135, alpha: 0.96)
    )

    /// Primary text — neutral graphite ink.
    static let ink = dynamic(
        NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.19, alpha: 0.92),
        NSColor(calibratedRed: 0.92, green: 0.93, blue: 0.95, alpha: 0.92)
    )

    static let inkSecondary = dynamic(
        NSColor(calibratedRed: 0.26, green: 0.27, blue: 0.29, alpha: 0.72),
        NSColor(calibratedRed: 0.78, green: 0.79, blue: 0.82, alpha: 0.74)
    )

    static let hairline = dynamic(
        NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.19, alpha: 0.10),
        NSColor(calibratedRed: 0.88, green: 0.89, blue: 0.91, alpha: 0.12)
    )

    /// Primary card background — a quiet neutral layer above glass.
    static let card = dynamic(
        NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.62),
        NSColor(calibratedRed: 0.20, green: 0.23, blue: 0.28, alpha: 0.68)
    )

    /// Content-layer card on top of a Liquid Glass surface (text input).
    /// Translucent enough to preserve the sampled glass while keeping text crisp;
    /// the HIG reserves glass for the floating control layer, not content.
    /// Radius pairs with the panel: 22 (panel) - 14 (inset) ≈ 8–12, keeping
    /// the card concentric with the panel curve.
    static let contentCard = dynamic(
        NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.84),
        NSColor(calibratedRed: 0.17, green: 0.18, blue: 0.20, alpha: 0.78)
    )

    /// Soft result surface that keeps grammar sections on the glass plane.
    static let resultCard = dynamic(
        NSColor(calibratedRed: 0.98, green: 0.975, blue: 0.96, alpha: 0.14),
        NSColor(calibratedRed: 0.22, green: 0.21, blue: 0.20, alpha: 0.16)
    )

    /// Subtle card or callout background.
    static let cardSubtle = dynamic(
        NSColor(calibratedRed: 0.20, green: 0.19, blue: 0.18, alpha: 0.045),
        NSColor(calibratedRed: 0.91, green: 0.91, blue: 0.92, alpha: 0.07)
    )

    /// Subtle card stroke border.
    static let cardBorder = dynamic(
        NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.21, alpha: 0.10),
        NSColor(calibratedRed: 0.91, green: 0.91, blue: 0.92, alpha: 0.12)
    )

    /// High quality inner window border.
    static let panelBorder = dynamic(
        NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.21, alpha: 0.12),
        NSColor(calibratedRed: 0.91, green: 0.91, blue: 0.92, alpha: 0.14)
    )

    /// Neutral wash used to tint Liquid Glass surfaces without adding a colored cast.
    /// The material provides depth; the clay accent is reserved for interaction.
    /// Kept moderate: enough to neutralize arbitrary backdrops while preserving material.
    static let glassTint = dynamic(
        NSColor(calibratedRed: 1.0, green: 0.995, blue: 0.985, alpha: 0.22),
        NSColor(calibratedRed: 0.84, green: 0.85, blue: 0.87, alpha: 0.18)
    )

    /// Muted clay accent — reserved for actions, selection, and status.
    static let accent = dynamic(
        NSColor(calibratedRed: 0.67, green: 0.39, blue: 0.20, alpha: 1.0),
        NSColor(calibratedRed: 0.93, green: 0.62, blue: 0.34, alpha: 1.0)
    )

    static let onAccent = dynamic(
        .white,
        NSColor(calibratedRed: 0.10, green: 0.085, blue: 0.07, alpha: 0.96)
    )

    static let accentSoft = dynamic(
        NSColor(calibratedRed: 0.67, green: 0.39, blue: 0.20, alpha: 0.10),
        NSColor(calibratedRed: 0.93, green: 0.62, blue: 0.34, alpha: 0.14)
    )

    /// Correction red (original words).
    static let wrong = dynamic(
        NSColor(calibratedRed: 0.80, green: 0.18, blue: 0.16, alpha: 1.0),
        NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.42, alpha: 1.0)
    )

    static let wrongSoft = dynamic(
        NSColor(calibratedRed: 0.80, green: 0.18, blue: 0.16, alpha: 0.10),
        NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.42, alpha: 0.16)
    )

    /// Fixed green (corrected words).
    static let fixed = dynamic(
        NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.28, alpha: 1.0),
        NSColor(calibratedRed: 0.40, green: 0.80, blue: 0.52, alpha: 1.0)
    )

    static let fixedSoft = dynamic(
        NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.28, alpha: 0.055),
        NSColor(calibratedRed: 0.40, green: 0.80, blue: 0.52, alpha: 0.09)
    )
}

/// Layered soft shadow, used on the floating panels.
struct LayeredShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 1)
            .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
    }
}

extension View {
    func layeredShadow() -> some View { modifier(LayeredShadowModifier()) }
}
