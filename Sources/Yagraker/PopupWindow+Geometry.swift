import AppKit

extension PopupWindow {
    struct AnchoredPlacement: Equatable {
        let origin: NSPoint
        let isAnchoredAbove: Bool
    }

    /// Pure geometric placement for a floating panel anchored to a screen rectangle.
    /// Prefers positioning directly below the anchor; flips above if space is constrained.
    nonisolated static func calculateAnchoredPlacement(
        near anchorRect: NSRect,
        panelSize: NSSize,
        visibleFrame: NSRect,
        screenMargin: CGFloat = 8,
        anchorGap: CGFloat = 8
    ) -> AnchoredPlacement {
        var x = anchorRect.minX
        let minX = visibleFrame.minX + screenMargin
        let maxX = visibleFrame.maxX - screenMargin - panelSize.width
        if maxX >= minX {
            x = min(max(x, minX), maxX)
        } else {
            x = minX
        }

        let belowTop = anchorRect.minY - anchorGap
        let belowY = belowTop - panelSize.height

        let aboveY = anchorRect.maxY + anchorGap
        let aboveTop = aboveY + panelSize.height

        let canFitBelow = belowY >= visibleFrame.minY + screenMargin
        let canFitAbove = aboveTop <= visibleFrame.maxY - screenMargin

        var y: CGFloat
        let isAbove: Bool
        if canFitBelow {
            y = belowY
            isAbove = false
        } else if canFitAbove {
            y = aboveY
            isAbove = true
        } else {
            let spaceBelow = anchorRect.minY - visibleFrame.minY
            let spaceAbove = visibleFrame.maxY - anchorRect.maxY
            if spaceBelow >= spaceAbove {
                y = belowY
                isAbove = false
            } else {
                y = aboveY
                isAbove = true
            }
            let minY = visibleFrame.minY + screenMargin
            let maxY = visibleFrame.maxY - screenMargin - panelSize.height
            if maxY >= minY {
                y = min(max(y, minY), maxY)
            } else {
                y = minY
            }
        }

        return AnchoredPlacement(origin: NSPoint(x: round(x), y: round(y)), isAnchoredAbove: isAbove)
    }

    static func constrainedSize(
        _ proposedSize: NSSize,
        minimumSize: NSSize,
        maximumSize: NSSize
    ) -> NSSize {
        let maximumWidth = max(minimumSize.width, maximumSize.width)
        let maximumHeight = max(minimumSize.height, maximumSize.height)
        return NSSize(
            width: min(max(proposedSize.width, minimumSize.width), maximumWidth),
            height: min(max(proposedSize.height, minimumSize.height), maximumHeight)
        )
    }

    static func framesMatch(_ a: NSRect, _ b: NSRect, tolerance: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}
