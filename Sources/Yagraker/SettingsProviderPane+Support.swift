import SwiftUI
import YagrakerCore

extension SettingsProviderPane {

    var providerDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    var providerActions: some View {
        HStack(alignment: .center, spacing: 8) {
            if let validationMessage = viewModel.validationMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: viewModel.validationSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(viewModel.validationSucceeded ? Theme.fixed : Theme.wrong)
                    Text(validationMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let saveMessage = viewModel.saveMessage {
                Label(saveMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.fixed)
            }

            Spacer(minLength: 12)

            ThemedMenu(
                title: taskName(viewModel.validationTask),
                options: LLMTask.allCases,
                label: { taskName($0) },
                isSelected: { $0 == viewModel.validationTask },
                width: 132,
                accessibilityLabel: l10n.t("settings.provider.validateTask"),
                onSelect: { viewModel.validationTask = $0 }
            )

            Button(l10n.t("settings.provider.save")) {
                persistProvider(showFeedback: true)
            }
            Button(viewModel.isValidating ? l10n.t("settings.provider.validating") : validateButtonTitle) {
                validateProvider()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(viewModel.isValidating)
            .keyboardShortcut(.defaultAction)
        }
    }


    func persistProvider(showFeedback: Bool) {
        viewModel.persistProvider(showFeedback: showFeedback, l10n: l10n, refreshConfiguration: refreshConfiguration)
    }

    func validateProvider() {
        viewModel.validateProvider(l10n: l10n, refreshConfiguration: refreshConfiguration)
    }


    func routeProvider(for task: LLMTask) -> LLMProviderKind {
        viewModel.routeProviders[task] ?? .gemini
    }

    func routeBinding(for task: LLMTask) -> Binding<LLMProviderKind> {
        Binding(
            get: { routeProvider(for: task) },
            set: { viewModel.routeProviders[task] = $0 }
        )
    }

    func draftModel(for provider: LLMProviderKind, task: LLMTask) -> String {
        viewModel.providerDrafts[provider]?.model(for: task)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func modelBinding(for provider: LLMProviderKind, task: LLMTask) -> Binding<String> {
        Binding(
            get: { viewModel.providerDrafts[provider]?.model(for: task) ?? "" },
            set: { model in
                guard var draft = viewModel.providerDrafts[provider] else { return }
                draft.setModel(model, for: task)
                viewModel.providerDrafts[provider] = draft
            }
        )
    }

    func setModel(_ model: String, for provider: LLMProviderKind, task: LLMTask) {
        modelBinding(for: provider, task: task).wrappedValue = model
    }

    func ensureModelsLoaded(for provider: LLMProviderKind) {
        viewModel.ensureModelsLoaded(for: provider, l10n: l10n)
    }

    func refreshModels(for provider: LLMProviderKind) {
        viewModel.refreshModels(for: provider, l10n: l10n)
    }

    func modelOptions(
        for provider: LLMProviderKind,
        task: LLMTask
    ) -> [LLMModel] {
        let catalog: [LLMModel]
        if case .loaded(let loaded) = viewModel.modelCatalogs[provider] {
            catalog = loaded
        } else {
            catalog = []
        }
        return catalog.filter { model in
            switch provider {
            case .qwen:
                // Qwen-MT models are translation-only, but translation itself
                // works with any model — general-purpose LLMs translate too.
                return task == .translation || !QwenService.isMachineTranslationModel(model.id)
            case .mimo:
                return MiMoService.isTextGenerationModel(model.id)
            case .gemini, .deepseek, .custom:
                return true
            }
        }
    }

    func modelCatalogMessage(for provider: LLMProviderKind, task: LLMTask) -> String {
        switch viewModel.modelCatalogs[provider] {
        case .failed(let message): return message
        case .loading: return l10n.t("settings.provider.loadingModels")
        case .loaded:
            return modelOptions(for: provider, task: task).isEmpty
                ? l10n.t("settings.provider.noModels")
                : l10n.t("settings.provider.refreshModelsHint")
        case .idle, .none:
            let hasKey = !(viewModel.providerDrafts[provider]?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return hasKey
                ? l10n.t("settings.provider.refreshModelsHint")
                : l10n.t("settings.provider.modelsNeedKey")
        }
    }

    func modelCatalogStatus(for provider: LLMProviderKind, task: LLMTask) -> String? {
        switch viewModel.modelCatalogs[provider] {
        case .failed(let message): return message
        case .loading: return l10n.t("settings.provider.loadingModels")
        case .loaded:
            return modelOptions(for: provider, task: task).isEmpty
                ? l10n.t("settings.provider.noModels")
                : nil
        case .idle: return modelCatalogMessage(for: provider, task: task)
        case .none: return nil
        }
    }

    func invalidateModelCatalog(for provider: LLMProviderKind) {
        viewModel.invalidateModelCatalog(for: provider)
    }

    func catalogInput(
        for provider: LLMProviderKind,
        drafts: [LLMProviderKind: ProviderDraft]
    ) -> ModelCatalogInput {
        let draft = drafts[provider]
        return ModelCatalogInput(
            apiKey: draft?.apiKey ?? "",
            customBaseURL: draft?.customBaseURL ?? "",
            qwenBaseURL: draft?.qwenBaseURL ?? "",
            mimoCluster: draft?.mimoCluster ?? .cn
        )
    }

    func providerName(_ provider: LLMProviderKind) -> String {
        switch provider {
        case .gemini: return "Gemini"
        case .qwen: return "Qwen"
        case .deepseek: return "DeepSeek"
        case .mimo: return "MiMo"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    func taskName(_ task: LLMTask) -> String {
        switch task {
        case .translation: return l10n.t("settings.provider.task.translation")
        case .deepRead: return l10n.t("settings.provider.task.deepRead")
        case .grammar: return l10n.t("settings.provider.task.grammar")
        }
    }

    func taskRouteHint(_ task: LLMTask) -> String {
        switch task {
        case .translation: return l10n.t("settings.provider.translationRouteHint")
        case .deepRead: return l10n.t("settings.provider.deepReadRouteHint")
        case .grammar: return l10n.t("settings.provider.grammarRouteHint")
        }
    }

    func modelAccessibilityLabel(_ task: LLMTask) -> String {
        switch task {
        case .translation: return l10n.t("settings.provider.translationModel")
        case .deepRead: return l10n.t("settings.provider.deepReadModel")
        case .grammar: return l10n.t("settings.provider.grammarModel")
        }
    }



    func modelPlaceholder(for provider: LLMProviderKind, task: LLMTask) -> String {
        let defaultModel = provider.defaultModel(for: task)
        if !defaultModel.isEmpty { return defaultModel }
        return provider == .qwen && task != .translation ? "qwen-plus" : "model-id"
    }


    var validateButtonTitle: String {
        l10n.t("settings.provider.validateTaskButton", taskName(viewModel.validationTask))
    }
}
