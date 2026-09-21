import AppKit

/// Owns the global/local event monitors used to dismiss a floating popup when
/// the user clicks outside it.
@MainActor
final class PopupDismissalMonitor {
    private var globalClickMonitor: Any?
    private var localMonitor: Any?

    func update(
        isVisible: Bool,
        isEnabled: Bool,
        panel: NSWindow,
        shouldDismiss: @escaping @MainActor () -> Bool,
        dismiss: @escaping @MainActor () -> Void
    ) {
        remove()
        guard isVisible, isEnabled else { return }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            Task { @MainActor in
                guard shouldDismiss() else { return }
                dismiss()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if event.window != panel, shouldDismiss() {
                dismiss()
            }
            return event
        }
    }

    func remove() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}
