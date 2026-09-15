import AppKit
import KeyboardShortcuts

/// Dynamic menu-bar surface. The menu is rebuilt immediately before opening so
/// localization, updater state, shortcut recordings, and in-memory history stay current.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem
    let menu = NSMenu()
    private var languageObserver: NSObjectProtocol?

    private let shortcutNames: [KeyboardShortcuts.Name] = [
        .checkGrammar, .translate, .openTranslation, .openDeepRead,
    ]

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = ReIconAsset.menuBarPenSparkle
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel("Yagraker")
            button.toolTip = "Yagraker"
        }
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()

        languageObserver = NotificationCenter.default.addObserver(
            forName: L10n.languageChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildMenu() }
        }
    }

    deinit {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        KeyboardShortcuts.disable(shortcutNames)
    }

    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.enable(shortcutNames)
    }

    func rebuildMenu() {
        menu.removeAllItems()
        let l10n = L10n.shared

        menu.addItem(actionItem(
            title: l10n.t("menu.checkSelected"),
            symbol: "character.cursor.ibeam",
            action: #selector(checkSelected),
            shortcut: .checkGrammar
        ))
        menu.addItem(.separator())

        menu.addItem(actionItem(
            title: l10n.t("menu.quickTranslate"),
            symbol: "character.bubble",
            action: #selector(openTranslation),
            shortcut: .openTranslation
        ))
        menu.addItem(actionItem(
            title: l10n.t("menu.deepRead"),
            symbol: "book.pages",
            action: #selector(openDeepRead),
            shortcut: .openDeepRead
        ))
        menu.addItem(actionItem(
            title: l10n.t("menu.translateSelection"),
            symbol: "text.bubble",
            action: #selector(translateSelection),
            shortcut: .translate
        ))

        menu.addItem(.separator())
        let recentItem = NSMenuItem(
            title: l10n.t("menu.openRecent"),
            action: nil,
            keyEquivalent: ""
        )
        recentItem.image = symbol("clock.arrow.circlepath")
        recentItem.submenu = recentMenu()
        menu.addItem(recentItem)

        menu.addItem(.separator())
        let updateItem = actionItem(
            title: appState.updater.menuTitle,
            symbol: "arrow.triangle.2.circlepath",
            action: #selector(checkForUpdates)
        )
        updateItem.isEnabled = appState.updater.canCheckForUpdates && !appState.updater.isChecking
        menu.addItem(updateItem)

        menu.addItem(actionItem(
            title: l10n.t("menu.settings") + "…",
            symbol: "gearshape",
            action: #selector(openSettings),
            keyEquivalent: ",",
            modifierMask: [.command]
        ))
        menu.addItem(.separator())
        menu.addItem(actionItem(
            title: l10n.t("menu.quit"),
            symbol: "power",
            action: #selector(quit),
            keyEquivalent: "q",
            modifierMask: [.command]
        ))
    }

    private func recentMenu() -> NSMenu {
        let submenu = NSMenu()
        let l10n = L10n.shared
        if appState.grammar.history.isEmpty {
            let empty = NSMenuItem(title: l10n.t("menu.noRecent"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for (index, entry) in appState.grammar.history.enumerated() {
                let oneLine = entry.originalText
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = String(oneLine.prefix(54)) + (oneLine.count > 54 ? "…" : "")
                let item = NSMenuItem(
                    title: "\(entry.timeLabel)  \(preview)",
                    action: #selector(openHistoryEntry(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                submenu.addItem(item)
            }
            submenu.addItem(.separator())
            let clear = NSMenuItem(
                title: l10n.t("menu.clearHistory"),
                action: #selector(clearHistory),
                keyEquivalent: ""
            )
            clear.target = self
            clear.image = symbol("trash")
            submenu.addItem(clear)
        }
        return submenu
    }

    private func actionItem(
        title: String,
        symbol symbolName: String,
        action: Selector,
        shortcut: KeyboardShortcuts.Name? = nil,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.image = symbol(symbolName)
        item.keyEquivalentModifierMask = modifierMask
        if let shortcut {
            item.setShortcut(for: shortcut)
        }
        item.isEnabled = true
        return item
    }

    private func symbol(_ name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    // MARK: Actions

    @objc private func checkSelected() { appState.handleHotkey() }
    @objc private func translateSelection() { appState.handleTranslateHotkey() }
    @objc private func openTranslation() { appState.openTool(.translation) }
    @objc private func openDeepRead() { appState.openTool(.deepRead) }
    @objc private func openSettings() { appState.openSettings() }
    @objc private func checkForUpdates() { appState.updater.checkForUpdates() }
    @objc private func clearHistory() { appState.clearHistory() }

    @objc private func openHistoryEntry(_ sender: NSMenuItem) {
        guard appState.grammar.history.indices.contains(sender.tag) else { return }
        appState.openHistory(appState.grammar.history[sender.tag])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
