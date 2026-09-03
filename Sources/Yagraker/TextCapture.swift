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

    /// `AXFocusedApplication → AXFocusedUIElement → AXSelectedText`.
    static func readSelectedText(for application: NSRunningApplication? = nil) -> String? {
        guard isAccessibilityGranted else { return nil }
        let app: AXUIElement
        if let application {
            app = AXUIElementCreateApplication(application.processIdentifier)
        } else {
            let systemWide = AXUIElementCreateSystemWide()
            var appValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appValue) == .success,
                  let appValue else { return nil }
            app = unsafeBitCast(appValue, to: AXUIElement.self)
        }
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue else { return nil }
        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedValue) == .success else {
            return nil
        }
        return selectedValue as? String
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
