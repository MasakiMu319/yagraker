import AppKit
import YagrakerCore

extension PopupWindow {
    func positionPanel(anchoringTo anchorRect: NSRect? = nil) {
        let size = targetPanelSize()

        if let anchorRect {
            positionPanel(near: anchorRect, size: size)
            return
        }

        isAnchoredAbove = false

        if let topLeft = SettingsStore.shared.panelTopLeft {
            setFrameKeepingTopLeft(size, topLeft: topLeft)
            return
        }
        // First run: center horizontally on the screen with the mouse, upper third.
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screen = screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? screens.first ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - visible.height / 3 - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func positionPanel(near anchorRect: NSRect, size: NSSize) {
        let screens = NSScreen.screens
        let anchorCenter = NSPoint(x: anchorRect.midX, y: anchorRect.midY)
        let screen = screens.first { NSMouseInRect(anchorCenter, $0.frame, false) }
            ?? screens.first { $0.frame.intersects(anchorRect) }
            ?? panel.screen
            ?? screens.first
            ?? NSScreen.main
        guard let screen else { return }

        let placement = Self.calculateAnchoredPlacement(
            near: anchorRect,
            panelSize: size,
            visibleFrame: screen.visibleFrame,
            screenMargin: Self.screenMargin,
            anchorGap: Self.anchorGap
        )
        isAnchoredAbove = placement.isAnchoredAbove
        panel.setFrame(NSRect(origin: placement.origin, size: size), display: true)
    }

    func setFrameKeepingTopLeft(_ size: NSSize, topLeft: NSPoint) {
        panel.setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true)
    }

    func persistPosition() {
        let frame = panel.frame
        SettingsStore.shared.panelTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
    }
}
