import AppKit
import SwiftUI
import YagrakerCore

/// Hosts the popup SwiftUI content in a floating, non-activating panel:
/// - user-resizable width and height; automatic height stays within the visible screen
/// - click-outside dismisses unless pinned; position persisted across sessions
@MainActor
final class PopupWindow: NSObject, NSWindowDelegate {

    static let panelStyleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .resizable]
    static let defaultSize = NSSize(width: 481, height: 373)
    static let minimumWidth: CGFloat = 440
    static let minimumHeight: CGFloat = 240
    nonisolated static let anchorGap: CGFloat = 8
    nonisolated static let screenMargin: CGFloat = 8

    static var isTestingEnvironment: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    private let appState: AppState
    private let panel: PopupPanel
    private let hostingView: NSHostingView<AnyView>
    private let dismissalMonitor = PopupDismissalMonitor()

    private var heightSettleTask: Task<Void, Never>?
    private var settleAnchorFrame: NSRect?
    private var manuallyResizedHeight: CGFloat?
    private var isLiveResizing = false
    private var isUserDragging = false
    private var isAnchoredAbove = false

    init(appState: AppState) {
        self.appState = appState
        let storedSize = SettingsStore.shared.panelSize
        let initialSize = storedSize ?? Self.defaultSize
        manuallyResizedHeight = storedSize?.height

        panel = PopupPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: Self.panelStyleMask,
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: Self.minimumWidth, height: Self.minimumHeight)

        let rootView = PopupView(grammar: appState.grammar)
            .environmentObject(appState)
            .environmentObject(appState.toolPanelModel)
            .environmentObject(L10n.shared)
        hostingView = PopupHostingView(rootView: AnyView(rootView))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView
        if let contentView = panel.contentView {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        super.init()
        panel.delegate = self
        panel.onCancel = { [weak appState] in
            appState?.dismissPopup()
        }
    }

    // MARK: Show / close

    func show(anchoringTo anchorRect: NSRect? = nil) {
        positionPanel(anchoringTo: anchorRect)
        if !Self.isTestingEnvironment {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            focusInput()
        } else {
            panel.orderFrontRegardless()
        }
        updateMonitors()
        scheduleHeightSettle()
    }

    func close() {
        heightSettleTask?.cancel()
        heightSettleTask = nil
        settleAnchorFrame = nil
        isLiveResizing = false
        isUserDragging = false
        isAnchoredAbove = false
        dismissalMonitor.remove()
        panel.close()
    }

    var isVisible: Bool { panel.isVisible }
    var currentSize: NSSize { panel.frame.size }

    // MARK: Focus

    /// Give the manual-input editor keyboard focus when the panel opens idle.
    func focusInput() {
        if let textView = EditorRegistry.shared.textView {
            panel.makeFirstResponder(textView)
            textView.moveToEndOfDocument(nil)
        }
    }

    // MARK: Position

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

    private func positionPanel(anchoringTo anchorRect: NSRect? = nil) {
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

    private func setFrameKeepingTopLeft(_ size: NSSize, topLeft: NSPoint) {
        panel.setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true)
    }

    func windowDidMove(_ notification: Notification) {
        // Only persist moves the user initiated. A window manager (e.g. Wins
        // edge snapping) repositioning the panel right after a drop must not
        // overwrite the saved position.
        guard isUserDragging else { return }
        persistPosition()
    }

    /// Keeps `AppState.panelHeight` in sync across user resizes and
    /// programmatic frame changes, so content can flex with the panel.
    func windowDidResize(_ notification: Notification) {
        appState.panelHeight = panel.frame.height
    }

    private func persistPosition() {
        let frame = panel.frame
        SettingsStore.shared.panelTopLeft = CGPoint(x: frame.minX, y: frame.maxY)
    }

    // MARK: Sizing

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


    private static var minimumPanelSize: NSSize {
        NSSize(width: minimumWidth, height: minimumHeight)
    }

    private var maximumPanelSize: NSSize {
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

    private var dragStartOrigin: NSPoint?
    private var dragStartMouseLocation: NSPoint?

    func moveManually(by translation: CGSize) {
        guard panel.isVisible else { return }
        if !isUserDragging {
            heightSettleTask?.cancel()
            heightSettleTask = nil
            isUserDragging = true
            isAnchoredAbove = false
            stopFrameAnimation()
            dragStartOrigin = panel.frame.origin
            dragStartMouseLocation = NSEvent.mouseLocation
        }

        let currentMouse = NSEvent.mouseLocation
        if let startMouse = dragStartMouseLocation,
           let startOrigin = dragStartOrigin,
           currentMouse != startMouse {
            let dx = currentMouse.x - startMouse.x
            let dy = currentMouse.y - startMouse.y
            panel.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        } else {
            panel.setFrameOrigin(
                NSPoint(
                    x: panel.frame.origin.x + translation.width,
                    y: panel.frame.origin.y - translation.height
                )
            )
        }
    }

    func endManualMove() {
        guard isUserDragging else { return }
        isUserDragging = false
        dragStartOrigin = nil
        dragStartMouseLocation = nil
        persistPosition()
        settleAnchorFrame = panel.frame
        if panel.isVisible {
            scheduleHeightSettle()
        }
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard panel.inLiveResize else { return }
        beginManualResize()
    }

    func beginManualResize() {
        heightSettleTask?.cancel()
        heightSettleTask = nil
        settleAnchorFrame = nil
        isLiveResizing = true
        isAnchoredAbove = false
        stopFrameAnimation()
    }

    /// Interrupts any in-flight frame animation (e.g. a height settle still
    /// animating) so it cannot fight an incoming drag or resize — an active
    /// animator keeps writing its stale target frame every tick.
    private func stopFrameAnimation() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().setFrame(panel.frame, display: false)
        }
    }

    func resizeManually(to proposedSize: NSSize) {
        let size = Self.constrainedSize(
            proposedSize,
            minimumSize: Self.minimumPanelSize,
            maximumSize: maximumPanelSize
        )
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        manuallyResizedHeight = size.height
        setFrameKeepingTopLeft(size, topLeft: topLeft)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        Self.constrainedSize(
            frameSize,
            minimumSize: Self.minimumPanelSize,
            maximumSize: maximumPanelSize
        )
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard isLiveResizing else { return }
        endManualResize()
    }

    func endManualResize() {
        isLiveResizing = false
        let size = Self.constrainedSize(
            panel.frame.size,
            minimumSize: Self.minimumPanelSize,
            maximumSize: maximumPanelSize
        )
        manuallyResizedHeight = size.height
        SettingsStore.shared.panelSize = size
    }

    // MARK: Click-outside dismissal

    func updateMonitors() {
        dismissalMonitor.update(
            isVisible: panel.isVisible,
            isEnabled: !appState.isPinned && !Self.isTestingEnvironment,
            panel: panel,
            shouldDismiss: { [weak self] in
                self?.appState.isPinned == false
            },
            dismiss: { [weak self] in
                self?.appState.dismissPopup(restoreFocus: false)
            }
        )
    }

    func removeClickMonitor() {
        dismissalMonitor.remove()
    }

    func windowWillClose(_ notification: Notification) {
        heightSettleTask?.cancel()
        heightSettleTask = nil
        settleAnchorFrame = nil
        isLiveResizing = false
        isUserDragging = false
        dismissalMonitor.remove()
    }
}