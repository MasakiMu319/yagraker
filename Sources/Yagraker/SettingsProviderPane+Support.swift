import SwiftUI
import YagrakerCore

extension SettingsProviderPane {
    func providerField<Content: View>(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 176, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

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

    @ViewBuilder
    func providerHelp(for provider: LLMProviderKind) -> some View {
        let (label, url) = providerHelpLink(for: provider)
        if let url {
            Link(destination: url) {
                Label(label, systemImage: "arrow.up.right.square")
                    .font(.system(size: 12))
            }
        } else {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    func persistProvider(showFeedback: Bool) {
        viewModel.persistProvider(showFeedback: showFeedback, l10n: l10n, refreshConfiguration: refreshConfiguration)
    }

    func validateProvider() {
        viewModel.validateProvider(l10n: l10n, refreshConfiguration: refreshConfiguration)
    }

    func draftBinding<Value>(
        _ provider: LLMProviderKind,
        keyPath: WritableKeyPath<ProviderDraft, Value>
    ) -> Binding<Value> {
        Binding(
            get: { viewModel.providerDrafts[provider]![keyPath: keyPath] },
            set: { value in
                guard var draft = viewModel.providerDrafts[provider] else { return }
                draft[keyPath: keyPath] = value
                viewModel.providerDrafts[provider] = draft
            }
        )
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

    func clusterName(_ cluster: MiMoCluster) -> String {
        switch cluster {
        case .cn: return l10n.t("cluster.cn")
        case .sg: return l10n.t("cluster.sg")
        case .eu: return l10n.t("cluster.eu")
        }
    }

    func endpointLabel(for provider: LLMProviderKind) -> String {
        let draft = viewModel.providerDrafts[provider]!
        switch provider {
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        case .qwen:
            let base = draft.qwenBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return (base.isEmpty ? QwenService.defaultBaseURL : base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) + "/chat/completions"
        case .deepseek:
            return "https://api.deepseek.com/chat/completions"
        case .mimo:
            return draft.mimoCluster.baseURL + "/chat/completions"
        case .custom:
            let base = draft.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return (base.isEmpty ? "{base}" : base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) + "/chat/completions"
        }
    }

    func modelPlaceholder(for provider: LLMProviderKind, task: LLMTask) -> String {
        let defaultModel = provider.defaultModel(for: task)
        if !defaultModel.isEmpty { return defaultModel }
        return provider == .qwen && task != .translation ? "qwen-plus" : "model-id"
    }

    func providerHelpLink(for provider: LLMProviderKind) -> (String, URL?) {
        switch provider {
        case .gemini:
            return (l10n.t("provider.help.gemini"), URL(string: "https://aistudio.google.com/apikey"))
        case .qwen:
            return (l10n.t("provider.help.qwen"), URL(string: "https://bailian.console.aliyun.com/"))
        case .deepseek:
            return (l10n.t("provider.help.deepseek"), URL(string: "https://platform.deepseek.com/api_keys"))
        case .mimo:
            return (l10n.t("provider.help.mimo"), URL(string: "https://platform.xiaomimimo.com"))
        case .custom:
            return (l10n.t("provider.help.custom"), nil)
        }
    }

    var validateButtonTitle: String {
        l10n.t("settings.provider.validateTaskButton", taskName(viewModel.validationTask))
    }
}
