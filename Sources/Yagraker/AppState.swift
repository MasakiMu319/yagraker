import AppKit
import Foundation
import YagrakerCore

/// Central orchestrator for hotkeys, grammar checks, translation, history,
/// and panel state.
@MainActor
final class AppState: ObservableObject {

    // MARK: Panel state

    @Published var isPinned = SettingsStore.shared.isPinned {
        didSet {
            SettingsStore.shared.isPinned = isPinned
            popupWindow.updateMonitors()
        }
    }
    let grammar = GrammarCoordinator()

    /// Live panel height, kept in sync by `PopupWindow.windowDidResize` so
    /// content can flex with user-driven resizing.
    @Published var panelHeight: CGFloat = SettingsStore.shared.panelSize?.height
        ?? PopupWindow.defaultSize.height

    // MARK: Subsystems

    lazy var toolPanelModel: ToolPanelModel = {
        let model = ToolPanelModel()
        model.onSubmitGrammar = { [weak self] text in
            self?.startGrammarCheck(text: text, providerOverride: nil)
        }
        model.onModeChanged = { [weak self] _ in
            guard let self else { return }
            self.grammar.errorMessage = nil
            self.grammar.replacedNotice = nil
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.popupWindow.isVisible else { return }
                self.popupWindow.scheduleHeightSettle()
                self.popupWindow.focusInput()
            }
        }
        model.onInputChanged = { [weak self] newInput in
            guard let self else { return }
            let trimmed = newInput.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                var needsSettle = false
                if self.grammar.correctionResult != nil {
                    self.grammar.correctionResult = nil
                    self.grammar.originalText = ""
                    needsSettle = true
                }
                if self.grammar.replacedNotice != nil {
                    self.grammar.replacedNotice = nil
                }
                if self.toolPanelModel.hasOutput || self.toolPanelModel.generationPhase != .idle {
                    self.toolPanelModel.cancelGeneration(clearOutput: true)
                    needsSettle = true
                }
                if needsSettle && self.popupWindow.isVisible {
                    self.popupWindow.scheduleHeightSettle()
                }
                return
            }

            if self.toolPanelModel.mode == .grammar,
               self.grammar.correctionResult != nil,
               newInput != self.grammar.originalText {
                self.grammar.correctionResult = nil
                self.grammar.replacedNotice = nil
                if self.popupWindow.isVisible {
                    self.popupWindow.scheduleHeightSettle()
                }
            }

            if (self.toolPanelModel.mode == .translation || self.toolPanelModel.mode == .deepRead),
               self.toolPanelModel.generationPhase == .done,
               newInput != self.toolPanelModel.lastGeneratedInput {
                self.toolPanelModel.cancelGeneration(clearOutput: true)
                if self.popupWindow.isVisible {
                    self.popupWindow.scheduleHeightSettle()
                }
            }
        }
        return model
    }()
    let updater = UpdaterController()

    lazy var popupWindow = PopupWindow(appState: self)
    var settingsController: SettingsWindowController?

    private let externalAppContext = ExternalAppContext()
    private lazy var selectionCoordinator = SelectionCoordinator(externalAppContext: externalAppContext)

    init() {}

    // MARK: - Hotkey entry points

    /// ⇧⌘G — check the current selection (AX first, then menu/synthetic copy, clipboard fallback).
    func handleHotkey() {
        let (sourceApplication, anchorRect, accessibilityText) = resolveSelectionContext()
        Task {
            let (captured, hasDirectSelection) = await captureSelection(from: sourceApplication, accessibility: accessibilityText)

            guard let text = captured, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.showNoTextError(for: .grammar, anchorRect: anchorRect)
                return
            }
            guard ProviderResolver.configuredProviders(for: .grammar).isEmpty == false else {
                self.showConfigurationError(for: .grammar, anchorRect: anchorRect)
                return
            }
            self.startGrammarCheck(
                text: text,
                providerOverride: nil,
                replacementTarget: hasDirectSelection ? sourceApplication : nil,
                anchorRect: anchorRect
            )
        }
    }

    /// ⌥⌘T — translate the current selection in the Translate workspace.
    func handleTranslateHotkey() {
        let (sourceApplication, anchorRect, accessibilityText) = resolveSelectionContext()
        Task {
            let (captured, _) = await captureSelection(from: sourceApplication, accessibility: accessibilityText)

            guard let text = captured, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.showNoTextError(for: .translation, anchorRect: anchorRect)
                return
            }
            guard ProviderResolver.configuredProviders(for: .translation).isEmpty == false else {
                self.showConfigurationError(for: .translation, anchorRect: anchorRect)
                return
            }
            self.startTranslation(text: text, anchorRect: anchorRect)
        }
    }

    private func resolveSelectionContext() -> (sourceApplication: NSRunningApplication?, anchorRect: NSRect?, text: String?) {
        selectionCoordinator.resolveSelectionContext()
    }

    private func captureSelection(from application: NSRunningApplication?, accessibility: String?) async -> (String?, Bool) {
        await selectionCoordinator.captureSelection(from: application, accessibility: accessibility)
    }

    /// Open the panel in a mode without running anything.
    func openTool(_ mode: ToolPanelModel.Mode) {
        toolPanelModel.selectMode(mode)
        grammar.errorMessage = nil
        grammar.replacedNotice = nil
        popupWindow.show()
    }

    private func startTranslation(text: String, anchorRect: NSRect? = nil) {
        toolPanelModel.activate(mode: .translation, input: text, clearResults: true)
        grammar.errorMessage = nil
        grammar.replacedNotice = nil
        popupWindow.show(anchoringTo: anchorRect)
        toolPanelModel.startGeneration(mode: .translation, text: text)
    }

    // MARK: - Grammar

    func startGrammarCheck(
        text: String,
        providerOverride: LLMProviderKind?,
        replacementTarget: NSRunningApplication? = nil,
        anchorRect: NSRect? = nil
    ) {
        do {
            let kind = providerOverride ?? toolPanelModel.provider(for: .grammar)
            let resolved = try ProviderResolver.resolve(kind, task: .grammar)
            toolPanelModel.activate(mode: .grammar, input: text, clearResults: true)
            grammar.start(text: text, resolved: resolved, replacementTarget: replacementTarget)
            popupWindow.show(anchoringTo: anchorRect)
        } catch {
            grammar.errorMessage = L10n.shared.errorText(error)
            popupWindow.show(anchoringTo: anchorRect)
        }
    }

    func checkGrammar(request: GrammarCheckRequest, providerOverride: LLMProviderKind?, anchorRect: NSRect? = nil) {
        do {
            let kind = providerOverride ?? toolPanelModel.provider(for: .grammar)
            let resolved = try ProviderResolver.resolve(kind, task: .grammar)
            grammar.check(request: request, resolved: resolved)
            popupWindow.show(anchoringTo: anchorRect)
        } catch {
            grammar.errorMessage = L10n.shared.errorText(error)
            popupWindow.show(anchoringTo: anchorRect)
        }
    }

    func retry() {
        do {
            let kind = toolPanelModel.provider(for: .grammar)
            let resolved = try ProviderResolver.resolve(kind, task: .grammar)
            grammar.retry(currentInput: toolPanelModel.input, resolved: resolved)
        } catch {
            grammar.errorMessage = L10n.shared.errorText(error)
        }
    }

    func cancelGrammarCheck(clearResults: Bool) {
        grammar.cancel(clearResults: clearResults)
    }

    // MARK: - Grammar result actions

    func replaceOriginalText() {
        grammar.replaceOriginalText { [weak self] _ in
            self?.scheduleDismissAfterNotice()
        }
    }

    private func scheduleDismissAfterNotice() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard let self, self.grammar.replacedNotice != nil else { return }
            if self.isPinned {
                self.grammar.replacedNotice = nil
                self.grammar.correctionResult = nil
                self.grammar.originalText = ""
                self.toolPanelModel.input = ""
                if self.popupWindow.isVisible {
                    self.popupWindow.scheduleHeightSettle()
                }
            } else {
                self.dismissPopup()
            }
        }
    }

    func copyCorrectedText() {
        grammar.copyCorrectedText()
    }

    func openHistory(_ entry: GrammarHistoryEntry) {
        toolPanelModel.activate(mode: .grammar, input: entry.originalText, clearResults: true)
        grammar.openHistory(entry)
        popupWindow.show()
    }

    func clearHistory() {
        grammar.clearHistory()
    }

    func clearAll() {
        cancelGrammarCheck(clearResults: true)
        toolPanelModel.cancelGeneration(clearOutput: true)
        toolPanelModel.input = ""
        grammar.originalText = ""
        grammar.correctionResult = nil
        grammar.errorMessage = nil
        grammar.replacedNotice = nil
        if popupWindow.isVisible {
            popupWindow.scheduleHeightSettle()
            popupWindow.focusInput()
        }
    }

    // MARK: - Panel chrome

    func togglePin() { isPinned.toggle() }
    func dismissPopup(restoreFocus: Bool = true) {
        if grammar.isLoading { grammar.cancel(clearResults: false) }
        if toolPanelModel.isStreaming { toolPanelModel.cancelGeneration(clearOutput: true) }
        popupWindow.close()
        if restoreFocus { restoreExternalApplicationIfNeeded() }
    }
    func restoreExternalApplicationIfNeeded() {
        externalAppContext.restoreExternalApplicationIfNeeded()
    }

    private func currentExternalApplication() -> NSRunningApplication? {
        externalAppContext.currentExternalApplication()
    }

    // MARK: - Settings

    func showConfigurationError(for mode: ToolPanelModel.Mode, anchorRect: NSRect? = nil) {
        toolPanelModel.selectMode(mode)
        grammar.errorMessage = L10n.shared.errorText(LLMError.noProvider)
        popupWindow.show(anchoringTo: anchorRect)
    }

    private func showNoTextError(for mode: ToolPanelModel.Mode, anchorRect: NSRect? = nil) {
        toolPanelModel.selectMode(mode)
        grammar.errorMessage = L10n.shared.t("error.noTranslatableText")
        popupWindow.show(anchoringTo: anchorRect)
    }

    func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(appState: self)
        }
        settingsController?.show()
    }
}
