import AppKit
import Foundation
import YagrakerCore

/// Central orchestrator for hotkeys, grammar checks, translation, history,
/// and panel state.
@MainActor
final class AppState: ObservableObject {

    // MARK: Grammar state

    @Published var isLoading = false
    @Published var correctionResult: CorrectionResult?
    @Published var errorMessage: String?
    @Published var originalText = ""
    @Published var replacedNotice: String?

    // MARK: Panel state

    @Published var isPinned = SettingsStore.shared.isPinned {
        didSet {
            SettingsStore.shared.isPinned = isPinned
            popupWindow.updateMonitors()
        }
    }
    /// In-memory only, capped at 10 — intentionally never persisted (privacy).
    @Published private(set) var history: [GrammarHistoryEntry] = []

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
            self.errorMessage = nil
            self.replacedNotice = nil
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
                if self.correctionResult != nil {
                    self.correctionResult = nil
                    self.originalText = ""
                    needsSettle = true
                }
                if self.replacedNotice != nil {
                    self.replacedNotice = nil
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
               self.correctionResult != nil,
               newInput != self.originalText {
                self.correctionResult = nil
                self.replacedNotice = nil
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

    private var grammarTask: Task<Void, Never>?
    private var lastRequest: GrammarCheckRequest?
    private var replacementTargetApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    init() {
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.rememberExternalApplication(application)
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

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
        let sourceApplication = currentExternalApplication()
        SelectionReader.promptForAccessibilityIfNeeded()
        let selectionContext = SelectionReader.readSelection(for: sourceApplication)
        let anchorRect = selectionContext.bounds ?? SelectionReader.fallbackMouseAnchor()
        return (sourceApplication, anchorRect, selectionContext.text)
    }

    private func captureSelection(from application: NSRunningApplication?, accessibility: String?) async -> (String?, Bool) {
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

    /// Open the panel in a mode without running anything.
    func openTool(_ mode: ToolPanelModel.Mode) {
        toolPanelModel.selectMode(mode)
        errorMessage = nil
        replacedNotice = nil
        popupWindow.show()
    }

    private func startTranslation(text: String, anchorRect: NSRect? = nil) {
        toolPanelModel.activate(mode: .translation, input: text, clearResults: true)
        errorMessage = nil
        replacedNotice = nil
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
        replacementTargetApplication = replacementTarget
        originalText = text
        correctionResult = nil
        errorMessage = nil
        replacedNotice = nil
        toolPanelModel.activate(mode: .grammar, input: text, clearResults: true)
        checkGrammar(
            request: GrammarCheckRequest(text: text, reader: L10n.shared.reader),
            providerOverride: providerOverride,
            anchorRect: anchorRect
        )
    }

    func checkGrammar(request: GrammarCheckRequest, providerOverride: LLMProviderKind?, anchorRect: NSRect? = nil) {
        grammarTask?.cancel()
        let kind = providerOverride ?? toolPanelModel.provider(for: .grammar)
        do {
            let resolved = try ProviderResolver.resolve(kind, task: .grammar)
            lastRequest = request
            isLoading = true
            errorMessage = nil
            popupWindow.show(anchoringTo: anchorRect)
            grammarTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let result = try await resolved.service.checkGrammar(
                        request: request, apiKey: resolved.apiKey, model: resolved.model
                    )
                    guard !Task.isCancelled else { return }
                    // Spans are matched literally against the submission; when
                    // none match there is nothing safe to show or paste back.
                    guard !result.hasCorrections || result.splicingCorrections(into: request.text) != nil else {
                        throw LLMError.invalidResponse
                    }
                    self.isLoading = false
                    self.correctionResult = result
                    self.recordHistory(result)
                    self.popupWindow.scheduleHeightSettle()
                } catch {
                    guard !Task.isCancelled else { return }
                    self.isLoading = false
                    self.errorMessage = L10n.shared.errorText(error)
                }
            }
        } catch {
            isLoading = false
            errorMessage = L10n.shared.errorText(error)
            popupWindow.show(anchoringTo: anchorRect)
        }
    }

    func retry() {
        // Re-check the current input — the user may have edited it in the
        // result view. Keep the replacement target so Accept can still paste
        // back into the source app.
        let input = toolPanelModel.input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty {
            startGrammarCheck(
                text: toolPanelModel.input,
                providerOverride: nil,
                replacementTarget: replacementTargetApplication
            )
        } else if let lastRequest {
            checkGrammar(request: lastRequest, providerOverride: nil)
        }
    }

    func cancelGrammarCheck(clearResults: Bool) {
        grammarTask?.cancel()
        grammarTask = nil
        isLoading = false
        if clearResults {
            correctionResult = nil
            originalText = ""
        }
    }

    // MARK: - Grammar result actions

    /// Accept: reactivate the source app, then paste over its retained selection.
    /// Manual/history checks have no safe source target and therefore copy instead.
    func replaceOriginalText() {
        guard let result = correctionResult, result.hasCorrections else { return }
        let correctedText = textForReplacement(result)
        let target = replacementTargetApplication

        Task { [weak self] in
            guard let self else { return }
            var didPaste = false
            if let target,
               !target.isTerminated,
               target.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               target.activate(options: []) {
                for _ in 0..<20 {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                        TextCapture.pasteText(correctedText, targetPid: target.processIdentifier)
                        didPaste = true
                        break
                    }
                    try? await Task.sleep(nanoseconds: 25_000_000)
                }
            }
            if !didPaste {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(correctedText, forType: .string)
            }

            replacementTargetApplication = nil
            if didPaste, let first = result.corrections.first {
                replacedNotice = L10n.shared.t("popup.replacedPrefix")
                    + first.original
                    + L10n.shared.t("popup.replacedInfix")
                    + first.corrected
            } else {
                replacedNotice = L10n.shared.t("popup.copiedCorrected")
            }
            scheduleDismissAfterNotice()
        }
    }

    private func scheduleDismissAfterNotice() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard let self, self.replacedNotice != nil else { return }
            if self.isPinned {
                self.replacedNotice = nil
                self.correctionResult = nil
                self.originalText = ""
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
        guard let result = correctionResult else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textForReplacement(result), forType: .string)
    }

    /// Text written back into the source document. Splicing keeps everything
    /// outside the corrected spans byte-identical to what the user had.
    private func textForReplacement(_ result: CorrectionResult) -> String {
        result.splicingCorrections(into: originalText) ?? originalText
    }

    // MARK: - History (in-memory, last 10)

    private func recordHistory(_ result: CorrectionResult) {
        let entry = GrammarHistoryEntry(originalText: originalText, result: result)
        history.insert(entry, at: 0)
        if history.count > 10 {
            history.removeLast(history.count - 10)
        }
    }

    func openHistory(_ entry: GrammarHistoryEntry) {
        replacementTargetApplication = nil
        toolPanelModel.activate(mode: .grammar, input: entry.originalText, clearResults: true)
        originalText = entry.originalText
        correctionResult = entry.result
        errorMessage = nil
        replacedNotice = nil
        popupWindow.show()
    }

    func clearHistory() {
        history = []
    }

    func clearAll() {
        cancelGrammarCheck(clearResults: true)
        toolPanelModel.cancelGeneration(clearOutput: true)
        toolPanelModel.input = ""
        originalText = ""
        correctionResult = nil
        errorMessage = nil
        replacedNotice = nil
        if popupWindow.isVisible {
            popupWindow.scheduleHeightSettle()
            popupWindow.focusInput()
        }
    }

    // MARK: - Panel chrome

    func togglePin() { isPinned.toggle() }
    func dismissPopup(restoreFocus: Bool = true) {
        if isLoading { cancelGrammarCheck(clearResults: false) }
        if toolPanelModel.isStreaming { toolPanelModel.cancelGeneration(clearOutput: true) }
        popupWindow.close()
        if restoreFocus { restoreExternalApplicationIfNeeded() }
    }
    func restoreExternalApplicationIfNeeded() {
        guard !PopupWindow.isTestingEnvironment else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
                  NSApp.keyWindow == nil,
                  let application = lastExternalApplication,
                  !application.isTerminated else { return }
            application.activate(options: [])
        }
    }

    private func currentExternalApplication() -> NSRunningApplication? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            rememberExternalApplication(frontmost)
        }
        return lastExternalApplication
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated else { return }
        lastExternalApplication = application
    }

    // MARK: - Settings

    func showConfigurationError(for mode: ToolPanelModel.Mode, anchorRect: NSRect? = nil) {
        toolPanelModel.selectMode(mode)
        errorMessage = L10n.shared.errorText(LLMError.noProvider)
        popupWindow.show(anchoringTo: anchorRect)
    }

    private func showNoTextError(for mode: ToolPanelModel.Mode, anchorRect: NSRect? = nil) {
        toolPanelModel.selectMode(mode)
        errorMessage = L10n.shared.t("error.noTranslatableText")
        popupWindow.show(anchoringTo: anchorRect)
    }

    func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(appState: self)
        }
        settingsController?.show()
    }
}
