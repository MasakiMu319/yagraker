import AppKit
import Foundation
import YagrakerCore

/// Owns the translation/deep-read streaming lifecycle and its Markdown snapshot source.
@MainActor
final class GenerationCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle, streaming, done, failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var output = ""
    @Published private(set) var outputMode: ToolPanelModel.Mode?
    @Published private(set) var streamSource = MarkdownStreamSource()
    private(set) var lastGeneratedInput = ""

    private var task: Task<Void, Never>?

    var isStreaming: Bool { phase == .streaming }
    var hasOutput: Bool { !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func start(
        mode: ToolPanelModel.Mode,
        text: String,
        resolved: ProviderResolver.Resolved
    ) {
        guard mode == .translation || mode == .deepRead else { return }
        let reader = L10n.shared.reader
        let target = TranslationTargetLanguage.inferred(from: text, for: reader)
        let systemPrompt: String
        switch mode {
        case .translation: systemPrompt = Prompts.translatorSystem(target: target)
        case .deepRead: systemPrompt = Prompts.deepReadSystem(target: target, reader: reader)
        case .grammar: return
        }

        task?.cancel()
        streamSource.finish()
        output = ""
        outputMode = mode
        lastGeneratedInput = text
        let source = MarkdownStreamSource()
        streamSource = source
        phase = .streaming

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = resolved.service.streamText(
                    task: resolved.task,
                    text: text,
                    systemPrompt: systemPrompt,
                    targetLanguage: target,
                    apiKey: resolved.apiKey,
                    model: resolved.model
                )
                for try await delta in stream {
                    if Task.isCancelled { break }
                    self.output += delta
                    source.update(with: self.output)
                }
                self.output = self.output.trimmingCharacters(in: .whitespacesAndNewlines)
                source.update(with: self.output)
                source.finish()
                if !Task.isCancelled {
                    self.phase = self.hasOutput
                        ? .done
                        : .failed(L10n.shared.t("error.emptyResult"))
                }
            } catch {
                source.finish()
                if !Task.isCancelled {
                    self.phase = .failed(L10n.shared.errorText(error))
                }
            }
        }
    }

    func cancel(clearOutput: Bool) {
        task?.cancel()
        task = nil
        if clearOutput {
            streamSource.finish()
            output = ""
            outputMode = nil
            lastGeneratedInput = ""
            streamSource = MarkdownStreamSource()
            phase = .idle
        } else {
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            streamSource.update(with: output)
            streamSource.finish()
            phase = hasOutput ? .done : .idle
        }
    }
}
