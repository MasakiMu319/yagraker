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

        var body: some View {
            configuration.label
                .frame(width: 28, height: 28)
                .contentShape(Circle())
                .glassEffect(.clear.interactive(), in: .circle)
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

        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(emphasis == .primary ? Theme.onAccent : Theme.ink)
                .padding(.horizontal, 11)
                .frame(minHeight: 25)
                .contentShape(Capsule())
                .glassEffect(glass, in: .capsule)
        }

        /// Interactive glass opts into the macOS 27 click-bounce response.
        private var glass: Glass {
            switch emphasis {
            case .primary: return .regular.tint(Theme.accent).interactive()
            case .secondary: return .regular.interactive()
            }
        }
    }
}

// MARK: - Circular Action Button (send / submit)

struct CircleActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.ink.opacity(0.35))
            .frame(width: 26, height: 26)
            .contentShape(Circle())
            .glassEffect(.regular.tint(Theme.accent).interactive(isEnabled), in: .circle)
    }
}

// MARK: - Mode selector segment button

struct CapsuleSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        // The enclosing glass capsule + selection glass already carry
        // hover/press feedback; an ink wash over glass reads muddy.
        configuration.label
            .contentShape(Rectangle())
    }
}