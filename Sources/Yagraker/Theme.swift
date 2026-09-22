import SwiftUI

/// Warm paper and ink theme shared by the app surfaces.
enum Theme {

    static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { $0.name == .darkAqua || $0.name == .vibrantDark || $0.name == .accessibilityHighContrastDarkAqua || $0.name == .accessibilityHighContrastVibrantDark ? dark : light }))
    }

    /// Panel background — warm paper (light) / warm charcoal (dark).
    static let paper = dynamic(
        NSColor(calibratedRed: 0.976, green: 0.965, blue: 0.949, alpha: 0.96),
        NSColor(calibratedRed: 0.118, green: 0.110, blue: 0.102, alpha: 0.96)
    )

    /// Primary text — warm ink.
    static let ink = dynamic(
        NSColor(calibratedRed: 44 / 255, green: 42 / 255, blue: 38 / 255, alpha: 0.92),
        NSColor(calibratedRed: 230 / 255, green: 227 / 255, blue: 220 / 255, alpha: 0.92)
    )

    static let inkSecondary = dynamic(
        NSColor(calibratedRed: 44 / 255, green: 42 / 255, blue: 38 / 255, alpha: 0.68),
        NSColor(calibratedRed: 230 / 255, green: 227 / 255, blue: 220 / 255, alpha: 0.70)
    )

    static let hairline = dynamic(
        NSColor(calibratedRed: 44 / 255, green: 42 / 255, blue: 38 / 255, alpha: 0.10),
        NSColor(calibratedRed: 230 / 255, green: 227 / 255, blue: 220 / 255, alpha: 0.12)
    )

    /// Primary card background — crisp warm white in light, elevated charcoal in dark.
    static let card = dynamic(
        NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.72),
        NSColor(calibratedRed: 0.165, green: 0.158, blue: 0.150, alpha: 0.65)
    )

    /// Content-layer card on top of a Liquid Glass surface (text input).
    /// Nearly opaque so text stays crisp against the glass sampling behind;
    /// the HIG reserves glass for the floating control layer, not content.
    /// Radius pairs with the panel: 22 (panel) - 14 (inset) ≈ 8–12, keeping
    /// the card concentric with the panel curve.
    static let contentCard = dynamic(
        NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.92),
        NSColor(calibratedRed: 0.155, green: 0.148, blue: 0.140, alpha: 0.88)
    )

    /// Subtle card or callout background.
    static let cardSubtle = dynamic(
        NSColor(calibratedRed: 44 / 255, green: 42 / 255, blue: 38 / 255, alpha: 0.04),
        NSColor(calibratedRed: 230 / 255, green: 227 / 255, blue: 220 / 255, alpha: 0.06)
    )

    /// Subtle card stroke border.
    static let cardBorder = dynamic(
        NSColor(calibratedRed: 44 / 255, green: 42 / 255, blue: 38 / 255, alpha: 0.07),
        NSColor(calibratedRed: 230 / 255, green: 227 / 255, blue: 220 / 255, alpha: 0.09)
    )

    /// High quality inner window border.
    static let panelBorder = dynamic(
        NSColor(calibratedRed: 44 / 255, green: 42 / 255, blue: 38 / 255, alpha: 0.12),
        NSColor(calibratedRed: 230 / 255, green: 227 / 255, blue: 220 / 255, alpha: 0.14)
    )

    /// Warm paper wash used to tint Liquid Glass surfaces so the material
    /// keeps the product identity instead of going neutral frosted gray.
    /// Kept faint on purpose: past ~0.3 alpha the glass turns into an opaque
    /// slab and stops reading as glass at all.
    static let glassTint = dynamic(
        NSColor(calibratedRed: 0.976, green: 0.965, blue: 0.949, alpha: 0.18),
        NSColor(calibratedRed: 0.140, green: 0.132, blue: 0.124, alpha: 0.28)
    )

    /// Warm clay accent.
    static let accent = dynamic(
        NSColor(calibratedRed: 0.72, green: 0.36, blue: 0.12, alpha: 1.0),
        NSColor(calibratedRed: 0.94, green: 0.55, blue: 0.25, alpha: 1.0)
    )

    static let onAccent = dynamic(
        .white,
        NSColor(calibratedRed: 0.10, green: 0.085, blue: 0.07, alpha: 0.96)
    )

    static let accentSoft = dynamic(
        NSColor(calibratedRed: 0.72, green: 0.36, blue: 0.12, alpha: 0.14),
        NSColor(calibratedRed: 0.94, green: 0.55, blue: 0.25, alpha: 0.20)
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
        NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.28, alpha: 0.10),
        NSColor(calibratedRed: 0.40, green: 0.80, blue: 0.52, alpha: 0.16)
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
