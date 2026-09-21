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

    let appState: AppState
    let panel: PopupPanel
    let hostingView: NSHostingView<AnyView>
    private let dismissalMonitor = PopupDismissalMonitor()

    var heightSettleTask: Task<Void, Never>?
    var settleAnchorFrame: NSRect?
    var manuallyResizedHeight: CGFloat?
    var isLiveResizing = false
    var isUserDragging = false
    var isAnchoredAbove = false

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

    // MARK: Window delegates



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