import AppKit

extension PopupWindow {
    func targetPanelSize() -> NSSize {
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let preferredHeight = manuallyResizedHeight ?? fitting.height
        let height = isShowingGrammarResult
            ? min(preferredHeight, fitting.height)
            : (preferredHeight > 0 ? preferredHeight : panel.frame.height)
        return Self.constrainedSize(
            NSSize(width: panel.frame.width, height: height),
            minimumSize: Self.minimumPanelSize,
            maximumSize: maximumPanelSize
        )
    }

    /// Debounced relayout — content updates arrive in bursts while streaming.
    func scheduleHeightSettle(animated: Bool = true) {
        heightSettleTask?.cancel()
        guard !isUserDragging else { return }
        heightSettleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            defer { self.settleAnchorFrame = nil }
            // If a window manager grabbed the panel right after the drag ended,
            // skip the resize animation instead of fighting the external frame.
            if let anchor = self.settleAnchorFrame,
               !Self.framesMatch(self.panel.frame, anchor) {
                return
            }
            self.resizePanel(animated: animated)
        }
    }

    static var minimumPanelSize: NSSize {
        NSSize(width: minimumWidth, height: minimumHeight)
    }

    var maximumPanelSize: NSSize {
        let screen = panel.screen
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let visibleSize = screen?.visibleFrame.size ?? NSSize(width: 1_440, height: 800)
        return NSSize(
            width: max(Self.minimumWidth, visibleSize.width),
            height: max(Self.minimumHeight, visibleSize.height * 0.8)
        )
    }

    func resizePanel(animated: Bool) {
        guard !isLiveResizing, !isUserDragging else { return }
        let size = targetPanelSize()
        var frame = panel.frame
        if isAnchoredAbove {
            let currentBottom = frame.minY
            let screen = panel.screen ?? NSScreen.main
            let visibleMaxY = (screen?.visibleFrame.maxY ?? (currentBottom + size.height)) - Self.screenMargin
            let targetMaxY = currentBottom + size.height
            if targetMaxY <= visibleMaxY {
                frame = NSRect(x: frame.minX, y: currentBottom, width: size.width, height: size.height)
            } else {
                let clampedY = max(screen?.visibleFrame.minY ?? 0, visibleMaxY - size.height)
                frame = NSRect(x: frame.minX, y: clampedY, width: size.width, height: size.height)
            }
        } else {
            let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
            frame = NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private var isShowingGrammarResult: Bool {
        appState.toolPanelModel.mode == .grammar && appState.grammar.correctionResult != nil
    }
}
