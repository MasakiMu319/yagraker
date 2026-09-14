import AppKit
import ApplicationServices

/// Reads the focused app's selected text via the Accessibility API,
/// captures selections via a synthetic ⌘C, and pastes corrected text back via
/// a synthetic ⌘V.
enum SelectionReader {

    static var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func promptForAccessibilityIfNeeded() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Reads the focused application's selected text and bounding box (in Cocoa screen coordinates).
    static func readSelection(for application: NSRunningApplication? = nil) -> (text: String?, bounds: NSRect?) {
        guard isAccessibilityGranted else { return (nil, nil) }
        let app: AXUIElement
        if let application {
            app = AXUIElementCreateApplication(application.processIdentifier)
        } else {
            let systemWide = AXUIElementCreateSystemWide()
            var appValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appValue) == .success,
                  let appValue else { return (nil, nil) }
            app = unsafeBitCast(appValue, to: AXUIElement.self)
        }
        // Guard against hung/frozen external applications blocking the UI
        AXUIElementSetMessagingTimeout(app, 0.2)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue else { return (nil, nil) }
        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)

        var selectedValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedValue)
        let text = selectedValue as? String

        let bounds = readBounds(for: focused)
        return (text, bounds)
    }

    /// `AXFocusedApplication → AXFocusedUIElement → AXSelectedText`.
    static func readSelectedText(for application: NSRunningApplication? = nil) -> String? {
        readSelection(for: application).text
    }

    /// Reads the screen bounds (in Cocoa screen coordinates) of the focused application's current text selection.
    static func readSelectionBounds(for application: NSRunningApplication? = nil) -> NSRect? {
        readSelection(for: application).bounds
    }

    /// Fallback anchor based on the mouse location when AX bounds are unavailable.
    /// Returns nil if the mouse is outside all screens or positioned within the system menu bar.
    static func fallbackMouseAnchor() -> NSRect? {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else {
            return nil
        }
        if mouse.y > screen.visibleFrame.maxY {
            return nil
        }
        return NSRect(x: mouse.x, y: mouse.y, width: 0, height: 0)
    }

    private static func readBounds(for focused: AXUIElement) -> NSRect? {
        var rangeValue: CFTypeRef?
        var rangeResult = AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        if rangeResult != .success {
            var rangesValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangesAttribute as CFString, &rangesValue) == .success,
               let ranges = rangesValue as? [AXValue],
               let first = ranges.first {
                rangeValue = first
                rangeResult = .success
            }
        }

        if rangeResult == .success, let rangeValue {
            var boundsValue: CFTypeRef?
            let boundsResult = AXUIElementCopyParameterizedAttributeValue(
                focused,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsValue
            )
            if boundsResult == .success, let boundsValue {
                var axRect = CGRect.zero
                if AXValueGetType(boundsValue as! AXValue) == .cgRect,
                   AXValueGetValue(boundsValue as! AXValue, .cgRect, &axRect),
                   !axRect.isNull, axRect.height > 0 {
                    if let cocoaRect = axRectToCocoaRect(axRect) {
                        return cocoaRect
                    }
                }
            }
        }

        // Fallback for compact controls (single-line input fields, search fields)
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXPositionAttribute as CFString, &posValue) == .success,
           AXUIElementCopyAttributeValue(focused, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let posValue, let sizeValue {
            var point = CGPoint.zero
            var size = CGSize.zero
            if AXValueGetValue(posValue as! AXValue, .cgPoint, &point),
               AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
               size.height > 0 && size.height <= 80, size.width > 0 {
                let axRect = CGRect(origin: point, size: size)
                if let cocoaRect = axRectToCocoaRect(axRect) {
                    return cocoaRect
                }
            }
        }

        return nil
    }

    /// Converts an AX / CoreGraphics screen rect (top-left origin, Y downwards)
    /// to a Cocoa screen rect (bottom-left origin of primary screen, Y upwards).
    static func axRectToCocoaRect(_ axRect: CGRect) -> NSRect? {
        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else { return nil }
        let primaryHeight = primaryScreen.frame.height
        let cocoaY = primaryHeight - axRect.origin.y - axRect.size.height
        let cocoaRect = NSRect(
            x: axRect.origin.x,
            y: cocoaY,
            width: max(1, axRect.size.width),
            height: max(1, axRect.size.height)
        )
        guard screens.contains(where: { $0.frame.intersects(cocoaRect) }) else {
            return nil
        }
        return cocoaRect
}
}

enum KeyboardSimulator {
    private static func post(_ key: CGKeyCode, targetPid: pid_t? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        keyUp?.flags = .maskCommand

        if let targetPid {
            keyDown?.postToPid(targetPid)
            usleep(15_000)
            keyUp?.postToPid(targetPid)
        } else {
            keyDown?.post(tap: .cghidEventTap)
            usleep(15_000)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    static func postCopy(targetPid: pid_t? = nil) { post(0x08, targetPid: targetPid) }  // kVK_ANSI_C
    static func postPaste(targetPid: pid_t? = nil) { post(0x09, targetPid: targetPid) } // kVK_ANSI_V
}

enum TextCapture {
    /// Snapshot the current clipboard so we can restore it after a synthetic copy.
    private static func snapshotItems() -> [[NSPasteboard.PasteboardType: Data]] {
        NSPasteboard.general.pasteboardItems?.map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                entry[type] = item.data(forType: type)
            }
            return entry
        } ?? []
    }

    private static func restoreItems(_ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    /// Triggers the "Copy" action via the target application's Menu Bar (Edit -> Copy).
    /// This works across applications like WeChat, Safari, Chrome, and Electron apps
    /// where selected text is not exposed via standard AXFocusedUIElement.
    static func performMenuCopy(for targetApp: NSRunningApplication?) -> Bool {
        guard SelectionReader.isAccessibilityGranted else { return false }
        guard let targetApp = targetApp ?? NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)

        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBarValue else { return false }
        let menuBar = unsafeBitCast(menuBarValue, to: AXUIElement.self)

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let menuBarItems = childrenValue as? [AXUIElement] else { return false }

        for menuBarItem in menuBarItems {
            var menuListValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(menuBarItem, kAXChildrenAttribute as CFString, &menuListValue) == .success,
                  let menus = menuListValue as? [AXUIElement] else { continue }

            for menu in menus {
                var menuItemsValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &menuItemsValue) == .success,
                      let menuItems = menuItemsValue as? [AXUIElement] else { continue }

                for item in menuItems {
                    var cmdCharValue: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(item, kAXMenuItemCmdCharAttribute as CFString, &cmdCharValue)
                    let cmdChar = (cmdCharValue as? String)?.uppercased()

                    var cmdModifiersValue: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(item, kAXMenuItemCmdModifiersAttribute as CFString, &cmdModifiersValue)
                    let modifiers = cmdModifiersValue as? Int ?? 0

                    var titleValue: CFTypeRef?
                    _ = AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue)
                    let title = titleValue as? String ?? ""

                    // Standard macOS Copy: Command+C (modifiers == 0 means Command modifier only)
                    let isCmdC = cmdChar == "C" && modifiers == 0
                    let isCopyTitle = title == "Copy" || title == "复制" || title == "拷贝" || title == "複製"

                    if isCmdC || isCopyTitle {
                        var enabledValue: CFTypeRef?
                        if AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabledValue) == .success,
                           let isEnabled = enabledValue as? Bool, !isEnabled {
                            // Copy menu item exists but is disabled -> no text is currently selected
                            return false
                        }

                        let pressResult = AXUIElementPerformAction(item, kAXPressAction as CFString)
                        return pressResult == .success
                    }
                }
            }
        }
        return false
    }

    /// Captures selected text preserving the user's previous clipboard contents.
    /// Order:
    /// 1. Menu Bar Copy action (`Edit -> Copy` via AX) — cleanest for WeChat, web views, etc.
    /// 2. Synthetic ⌘C with isolated event source and direct PID routing.
    @MainActor
    static func captureSelectedTextPreservingClipboard(targetApp: NSRunningApplication? = nil) async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotItems()
        defer { restoreItems(snapshot) }
        let before = pasteboard.changeCount

        // 1. Try Menu Bar Copy first
        if performMenuCopy(for: targetApp) {
            for _ in 0..<20 {
                if pasteboard.changeCount != before { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        // 2. Fall back to synthetic Cmd+C
        if pasteboard.changeCount == before {
            try? await Task.sleep(nanoseconds: 30_000_000)
            KeyboardSimulator.postCopy(targetPid: targetApp?.processIdentifier)

            for _ in 0..<30 {
                if pasteboard.changeCount != before { break }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
        }

        guard pasteboard.changeCount != before else {
            return nil
        }
        return pasteboard.string(forType: .string)
    }

    /// Replace the current selection with `text` via a synthetic ⌘V.
    @MainActor
    static func pasteText(_ text: String, targetPid: pid_t? = nil) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        KeyboardSimulator.postPaste(targetPid: targetPid)
    }

    /// Plain clipboard text used as the selection fallback.
    static var clipboardText: String? {
        NSPasteboard.general.string(forType: .string)
    }
}
