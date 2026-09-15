import AppKit

/// Resolves and captures the current selection from the owning external app.
@MainActor
struct SelectionCoordinator {
    let externalAppContext: ExternalAppContext

    func resolveSelectionContext() -> (sourceApplication: NSRunningApplication?, anchorRect: NSRect?, text: String?) {
        let sourceApplication = externalAppContext.currentExternalApplication()
        SelectionReader.promptForAccessibilityIfNeeded()
        let selectionContext = SelectionReader.readSelection(for: sourceApplication)
        let anchorRect = selectionContext.bounds ?? SelectionReader.fallbackMouseAnchor()
        return (sourceApplication, anchorRect, selectionContext.text)
    }

    func captureSelection(from application: NSRunningApplication?, accessibility: String?) async -> (String?, Bool) {
        if let accessibility,
           !accessibility.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (accessibility, true)
        }
        if let simulated = await TextCapture.captureSelectedTextPreservingClipboard(targetApp: application),
           !simulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (simulated, true)
        }
        if let clipboard = TextCapture.clipboardText,
           !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (clipboard, false)
        }
        return (nil, false)
    }
}
