import AppKit
import KeyboardShortcuts
import YagrakerCore

@MainActor
final class YagrakerAppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        CustomService.shared.baseURLProvider = {
            SettingsStore.shared.customBaseURL
        }
        QwenService.shared.baseURLProvider = {
            SettingsStore.shared.qwenBaseURL
        }
        MiMoService.shared.setCluster(SettingsStore.shared.mimoCluster)

        let state = AppState()
        appState = state
        menuBarController = MenuBarController(appState: state)

        registerGlobalShortcuts()
        state.updater.runSilentProbe()
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeyboardShortcuts.removeAllHandlers()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            appState.openSettings()
        }
        return true
    }

    private func registerGlobalShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .checkGrammar) { [weak appState] in
            Task { @MainActor in appState?.handleHotkey() }
        }
        KeyboardShortcuts.onKeyUp(for: .translate) { [weak appState] in
            Task { @MainActor in appState?.handleTranslateHotkey() }
        }
        KeyboardShortcuts.onKeyUp(for: .openTranslation) { [weak appState] in
            Task { @MainActor in appState?.openTool(.translation) }
        }
        KeyboardShortcuts.onKeyUp(for: .openDeepRead) { [weak appState] in
            Task { @MainActor in appState?.openTool(.deepRead) }
        }
    }
}
