import SwiftUI

/// Centralized Liquid Glass styling (macOS 26+, incl. the macOS 27
/// refinements: interactive click bounce and concentric corner geometry).
enum LiquidGlass {
    /// Floating popup panel corner radius.
    ///
    /// Panel content is inset by 14pt, so the 8–12pt radii of the inner cards
    /// (input card, result callouts) stay concentric with the panel curve:
    /// 22 - 14 = 8. This mirrors the macOS 27 concentricity guidance
    /// (`NSViewCornerRadius.containerConcentric`) without requiring AppKit
    /// subclassing inside SwiftUI content.
    static let panelCornerRadius: CGFloat = 22

    /// Panel chrome: a lightly neutralized Liquid Glass surface that preserves
    /// backdrop depth without letting the desktop color dominate the popup. Content
    /// is clipped into the glass shape, so no separate clip/border is needed.
    static let panelGlass: Glass = .regular.tint(Theme.glassTint)

    /// Under XCTest the windows are offscreen, so glass has no WindowServer
    /// backdrop to sample and renders as nothing — pixel-based UI tests then
    /// can't find the selection chrome. Tests get visually equivalent flat
    /// chrome instead; layout and hit-testing are identical.
    static var rendersGlass: Bool { !PopupWindow.isTestingEnvironment }
}

extension View {
    /// Chrome of the floating popup panel.
    @ViewBuilder
    func liquidGlassPanel() -> some View {
        if LiquidGlass.rendersGlass {
            glassEffect(
                LiquidGlass.panelGlass,
                in: .rect(cornerRadius: LiquidGlass.panelCornerRadius, style: .continuous)
            )
        } else {
            background(
                RoundedRectangle(cornerRadius: LiquidGlass.panelCornerRadius, style: .continuous)
                    .fill(Theme.paper)
            )
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlass.panelCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LiquidGlass.panelCornerRadius, style: .continuous)
                    .strokeBorder(Theme.panelBorder, lineWidth: 0.8)
            )
        }
    }

    /// Capsule chrome for floating controls (provider picker, menu labels).
    /// The `.interactive()` glass opts into the macOS 27 click-bounce response.
    @ViewBuilder
    func liquidGlassCapsule(tint: Color? = nil, cornerRadius: CGFloat? = nil) -> some View {
        if LiquidGlass.rendersGlass {
            let glass = tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive()
            if let cornerRadius {
                glassEffect(glass, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            } else {
                glassEffect(glass, in: .capsule)
            }
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius ?? 20, style: .continuous)
            background(
                shape
                    .fill(Theme.ink.opacity(0.05))
                    .overlay(
                        shape
                            .strokeBorder(Theme.cardBorder, lineWidth: 0.6)
                    )
            )
        }
    }
}

/// Standalone selection pill for segmented controls (popup mode selector,
/// settings tab bar), positioned by an animated `offset` in a ZStack behind
/// the segment labels.
///
/// Two constraints shape this design, both verified on-device:
/// - A pill *inside* a `GlassEffectContainer` is unioned into the container's
///   glass layer, which composites above non-glass siblings and covers the
///   labels. A standalone `glassEffect` view outside any container respects
///   ZStack order, so the labels draw above it.
/// - `glassEffectID` morphing is meant for merging/morphing simultaneously
///   present glass shapes; for a removal/insertion pair it swaps instantly
///   instead of sliding. A single persistent pill whose `offset` animates
///   glides visibly, matching the pre-glass behavior.
struct LiquidGlassPill: View {
    let tint: Color

    var body: some View {
        if LiquidGlass.rendersGlass {
            Color.clear
                .glassEffect(.regular.tint(tint), in: .capsule)
        } else {
            Capsule().fill(tint)
        }
    }
}
