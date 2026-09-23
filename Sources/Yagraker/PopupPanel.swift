import AppKit
import SwiftUI

/// Borderless floating panel that can take keyboard focus.
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Flipped container that insets the hosting view by the shadow padding.
final class FlippedHostingContainer: NSView {
    override var isFlipped: Bool { true }
}

final class PopupHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
