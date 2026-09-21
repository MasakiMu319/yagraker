import SwiftUI

// MARK: - FlowLayout (wraps correction chips / words)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let intrinsicSize = subview.sizeThatFits(.unspecified)
            let size = intrinsicSize.width > maxWidth && maxWidth.isFinite
                ? subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                : intrinsicSize
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                width = max(width, rowWidth)
                height += rowHeight + rowSpacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        width = max(width, rowWidth)
        height += rowHeight
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let intrinsicSize = subview.sizeThatFits(.unspecified)
            let size = intrinsicSize.width > bounds.width
                ? subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                : intrinsicSize
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - GhostButton

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(configuration: configuration)
    }

    private struct GhostButtonBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.ink.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.07 : 0.0)))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

// MARK: - Result actions

struct CapsuleActionButtonStyle: ButtonStyle {
    enum Emphasis: Equatable {
        case primary, secondary
    }

    let emphasis: Emphasis

    func makeBody(configuration: Configuration) -> some View {
        CapsuleActionButtonBody(
            configuration: configuration,
            emphasis: emphasis
        )
    }

    private struct CapsuleActionButtonBody: View {
        let configuration: Configuration
        let emphasis: Emphasis
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(emphasis == .primary ? Theme.onAccent : Theme.ink)
                .padding(.horizontal, 11)
                .frame(minHeight: 25)
                .background(Capsule().fill(backgroundColor))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            emphasis == .primary ? Color.white.opacity(0.18) : Theme.cardBorder,
                            lineWidth: 0.5
                        )
                )
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : (hovering ? 1.02 : 1.0))
                .animation(.spring(response: 0.18, dampingFraction: 0.75), value: hovering)
                .animation(.spring(response: 0.12, dampingFraction: 0.8), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }

        private var backgroundColor: Color {
            switch emphasis {
            case .primary:
                return Theme.accent.opacity(configuration.isPressed ? 0.85 : (hovering ? 0.94 : 1.0))
            case .secondary:
                return Theme.ink.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.08 : 0.04))
            }
        }
    }
}

// MARK: - Circular Action Button (send / submit)

struct CircleActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isEnabled ? Theme.paper : Theme.ink.opacity(0.35))
            .frame(width: 26, height: 26)
            .background(
                Circle()
                    .fill(
                        isEnabled
                            ? (hovering ? Theme.accent : Theme.ink)
                            : Theme.ink.opacity(0.08)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.92 : (isEnabled && hovering ? 1.06 : 1.0))
            .animation(.spring(response: 0.18, dampingFraction: 0.75), value: hovering)
            .animation(.spring(response: 0.12, dampingFraction: 0.8), value: configuration.isPressed)
            .contentShape(Circle())
            .onHover { hovering = $0 }
    }
}

// MARK: - Mode selector segment button

struct CapsuleSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ModeSegmentButtonBody(configuration: configuration, isSelected: isSelected)
    }

    private struct ModeSegmentButtonBody: View {
        let configuration: Configuration
        let isSelected: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .overlay(
                    Capsule().fill(overlayColor)
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }

        private var overlayColor: Color {
            if configuration.isPressed {
                return Theme.ink.opacity(isSelected ? 0.05 : 0.10)
            }
            return Theme.ink.opacity(!isSelected && hovering ? 0.06 : 0)
        }
    }
}
