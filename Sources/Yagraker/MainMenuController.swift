import AppKit

/// Installs the minimal application main menu required by AppKit's responder-chain
/// editing commands. Without an Edit menu, key equivalents such as ⌘V never reach
/// text fields in this otherwise menu-bar-only app.
@MainActor
final class MainMenuController {
    static let shared = MainMenuController()

    private var languageObserver: NSObjectProtocol?

    private init() {}

    func install() {
        rebuild()
        guard languageObserver == nil else { return }
        languageObserver = NotificationCenter.default.addObserver(
            forName: L10n.languageChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuild()
            }
        }
    }

    private func rebuild() {
        let menu = NSMenu()
        let editItem = NSMenuItem()
        editItem.submenu = editMenu()
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func editMenu() -> NSMenu {
        let l10n = L10n.shared
        let menu = NSMenu(title: l10n.t("menu.edit"))

        addItem(
            to: menu,
            title: l10n.t("menu.edit.undo"),
            action: #selector(UndoManager.undo),
            keyEquivalent: "z"
        )
        addItem(
            to: menu,
            title: l10n.t("menu.edit.redo"),
            action: #selector(UndoManager.redo),
            keyEquivalent: "z",
            modifiers: [.command, .shift]
        )
        menu.addItem(.separator())
        addItem(
            to: menu,
            title: l10n.t("menu.edit.cut"),
            action: #selector(NSTextView.cut(_:)),
            keyEquivalent: "x"
        )
        addItem(
            to: menu,
            title: l10n.t("menu.edit.copy"),
            action: #selector(NSTextView.copy(_:)),
            keyEquivalent: "c"
        )
        addItem(
            to: menu,
            title: l10n.t("menu.edit.paste"),
            action: #selector(NSTextView.paste(_:)),
            keyEquivalent: "v"
        )
        addItem(
            to: menu,
            title: l10n.t("menu.edit.pasteMatchStyle"),
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v",
            modifiers: [.command, .option, .shift]
        )
        addItem(
            to: menu,
            title: l10n.t("menu.edit.delete"),
            action: #selector(NSTextView.delete(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        addItem(
            to: menu,
            title: l10n.t("menu.edit.selectAll"),
            action: #selector(NSTextView.selectAll(_:)),
            keyEquivalent: "a"
        )

        return menu
    }

    private func addItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }
}
