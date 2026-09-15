import AppKit
import Foundation
import YagrakerCore

/// Owns grammar-check request lifecycle and its replacement target bookkeeping.
@MainActor
final class GrammarCoordinator: ObservableObject {
    @Published var isLoading = false
    @Published var correctionResult: CorrectionResult?
    @Published var errorMessage: String?
    @Published var originalText = ""
    @Published var replacedNotice: String?
    @Published private(set) var history: [GrammarHistoryEntry] = []

    private var task: Task<Void, Never>?
    private var lastRequest: GrammarCheckRequest?
    private var replacementTargetApplication: NSRunningApplication?

    func start(
        text: String,
        resolved: ProviderResolver.Resolved,
        replacementTarget: NSRunningApplication? = nil
    ) {
        replacementTargetApplication = replacementTarget
        originalText = text
        correctionResult = nil
        errorMessage = nil
        replacedNotice = nil

        let request = GrammarCheckRequest(text: text, reader: L10n.shared.reader)
        check(request: request, resolved: resolved)
    }

    func check(request: GrammarCheckRequest, resolved: ProviderResolver.Resolved) {
        task?.cancel()
        lastRequest = request
        isLoading = true
        errorMessage = nil

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await resolved.service.checkGrammar(
                    request: request, apiKey: resolved.apiKey, model: resolved.model
                )
                guard !Task.isCancelled else { return }
                guard !result.hasCorrections || result.splicingCorrections(into: request.text) != nil else {
                    throw LLMError.invalidResponse
                }
                self.isLoading = false
                self.correctionResult = result
                self.recordHistory(result)
            } catch {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                self.errorMessage = L10n.shared.errorText(error)
            }
        }
    }

    func retry(currentInput: String, resolved: ProviderResolver.Resolved) {
        let input = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty {
            start(text: currentInput, resolved: resolved, replacementTarget: replacementTargetApplication)
        } else if let lastRequest {
            check(request: lastRequest, resolved: resolved)
        }
    }

    func cancel(clearResults: Bool) {
        task?.cancel()
        task = nil
        isLoading = false
        if clearResults {
            correctionResult = nil
            originalText = ""
        }
    }

    /// Accept: reactivate the source app, then paste over its retained selection.
    /// Manual/history checks have no safe source target and therefore copy instead.
    func replaceOriginalText(completion: @escaping (String?) -> Void) {
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

            self.replacementTargetApplication = nil
            let notice: String
            if didPaste, let first = result.corrections.first {
                notice = L10n.shared.t("popup.replacedPrefix")
                    + first.original
                    + L10n.shared.t("popup.replacedInfix")
                    + first.corrected
            } else {
                notice = L10n.shared.t("popup.copiedCorrected")
            }
            self.replacedNotice = notice
            completion(notice)
        }
    }

    func copyCorrectedText() {
        guard let result = correctionResult else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textForReplacement(result), forType: .string)
    }

    func textForReplacement(_ result: CorrectionResult) -> String {
        result.splicingCorrections(into: originalText) ?? originalText
    }

    func openHistory(_ entry: GrammarHistoryEntry) {
        replacementTargetApplication = nil
        originalText = entry.originalText
        correctionResult = entry.result
        errorMessage = nil
        replacedNotice = nil
    }

    func clearHistory() {
        history = []
    }

    func clearAll() {
        cancel(clearResults: true)
        originalText = ""
        correctionResult = nil
        errorMessage = nil
        replacedNotice = nil
    }

    private func recordHistory(_ result: CorrectionResult) {
        let entry = GrammarHistoryEntry(originalText: originalText, result: result)
        history.insert(entry, at: 0)
        if history.count > 10 {
            history.removeLast(history.count - 10)
        }
    }
}
