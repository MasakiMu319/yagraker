import AppKit
import Combine
import Foundation
import YagrakerCore

/// State machine for the popup's manual-input text workflows.
@MainActor
final class ToolPanelModel: ObservableObject {

    typealias ProviderResolution = (LLMProviderKind, LLMTask) throws -> ProviderResolver.Resolved

    enum Mode: String, CaseIterable, Identifiable, Equatable, Hashable {
        case grammar, translation, deepRead
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .grammar: return "character.book.closed"
            case .translation: return "character.bubble"
            case .deepRead: return "book.pages"
            }
        }

        var task: LLMTask {
            switch self {
            case .grammar: return .grammar
            case .translation: return .translation
            case .deepRead: return .deepRead
            }
        }

        @MainActor
        func title(_ l10n: L10n) -> String {
            switch self {
            case .grammar: return l10n.t("tool.grammar")
            case .translation: return l10n.t("tool.translation")
            case .deepRead: return l10n.t("tool.deepRead")
            }
        }
    }

    @Published var mode: Mode = .grammar
    @Published var input: String = "" {
        didSet {
            guard input != oldValue else { return }
            onInputChanged?(input)
        }
    }
    @Published var selectedProvider: LLMProviderKind {
        didSet { SettingsStore.shared.setToolPanelProvider(selectedProvider, for: activeTask) }
    }
    @Published private(set) var generationPhase: GenerationCoordinator.Phase = .idle
    @Published private(set) var output: String = ""
    @Published private(set) var outputMode: Mode?
    @Published private(set) var streamSource = MarkdownStreamSource()
    private(set) var lastGeneratedInput: String = ""

    private let resolveProvider: ProviderResolution
    let generation = GenerationCoordinator()
    private var generationCancellables: [AnyCancellable] = []

    /// Wired by AppState: submitting in grammar mode starts a grammar check.
    var onSubmitGrammar: ((String) -> Void)?
    var onModeChanged: ((Mode) -> Void)?
    var onInputChanged: ((String) -> Void)?

    init(resolveProvider: @escaping ProviderResolution = ProviderResolver.resolve) {
        self.resolveProvider = resolveProvider
        selectedProvider = SettingsStore.shared.toolPanelProvider(for: .grammar)
        bindGeneration()
        refreshConfiguration()
    }

    private func bindGeneration() {
        generation.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.generationPhase = phase }
            .store(in: &generationCancellables)
        generation.$output
            .receive(on: RunLoop.main)
            .sink { [weak self] output in self?.output = output }
            .store(in: &generationCancellables)
        generation.$outputMode
            .receive(on: RunLoop.main)
            .sink { [weak self] outputMode in self?.outputMode = outputMode }
            .store(in: &generationCancellables)
        generation.$streamSource
            .receive(on: RunLoop.main)
            .sink { [weak self] source in self?.streamSource = source }
            .store(in: &generationCancellables)
    }

    var activeTask: LLMTask {
        mode.task
    }

    var configuredProviders: [LLMProviderKind] {
        ProviderResolver.configuredProviders(for: activeTask)
    }

    func provider(for task: LLMTask) -> LLMProviderKind {
        let configured = ProviderResolver.configuredProviders(for: task)
        let preferred = SettingsStore.shared.toolPanelProvider(for: task)
        return configured.contains(preferred) ? preferred : (configured.first ?? preferred)
    }

    var hasOutput: Bool {
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isStreaming: Bool { generationPhase == .streaming }

    func refreshConfiguration() {
        refreshConfiguration(for: activeTask)
    }

    func refreshConfiguration(for task: LLMTask) {
        let configured = ProviderResolver.configuredProviders(for: task)
        guard task == activeTask else { return }
        let preferred = SettingsStore.shared.toolPanelProvider(for: task)
        if configured.contains(preferred) {
            if selectedProvider != preferred {
                selectedProvider = preferred
            }
        } else if let first = configured.first, selectedProvider != first {
            selectedProvider = first
        } else if configured.isEmpty, selectedProvider != preferred {
            selectedProvider = preferred
        }
    }

    func activate(mode: Mode, input: String, clearResults: Bool) {
        selectMode(mode)
        if !input.isEmpty { self.input = input }
        if clearResults {
            cancelGeneration(clearOutput: true)
        }
    }

    func selectMode(_ mode: Mode) {
        let changed = self.mode != mode
        self.mode = mode
        refreshConfiguration(for: activeTask)
        if changed {
            onModeChanged?(mode)
        }
    }

    /// Enter / paste-to-submit from the editor.
    func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch mode {
        case .grammar:
            onSubmitGrammar?(input)
        case .translation, .deepRead:
            startGeneration(mode: mode, text: input)
        }
    }

    /// Stream a translation or close reading of `text`. Direction and wording
    /// follow the reader's UI language so every provider behaves the same.
    func startGeneration(mode: Mode, text: String) {
        selectMode(mode)
        generation.cancel(clearOutput: true)
        do {
            let resolved = try resolveProvider(provider(for: mode.task), mode.task)
            lastGeneratedInput = text
            generation.start(mode: mode, text: text, resolved: resolved)
        } catch {
            generationPhase = .failed(L10n.shared.errorText(error))
        }
    }

    func cancelGeneration(clearOutput: Bool) {
        generation.cancel(clearOutput: clearOutput)
        if clearOutput {
            lastGeneratedInput = ""
        }
    }

    func copyOutput() {
        guard hasOutput else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
    }
}
