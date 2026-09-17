import Combine
import Foundation
import YagrakerCore

/// Owns the provider editing session independently of the settings view's lifetime updates.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var routeProviders: [LLMTask: LLMProviderKind]
    @Published var credentialProvider: LLMProviderKind
    @Published var providerDrafts: [LLMProviderKind: ProviderDraft]
    @Published var modelCatalogs: [LLMProviderKind: ModelCatalogState] = [:]
    @Published var validationTask: LLMTask
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published var validationSucceeded = false
    @Published var saveMessage: String?
    private var originalAPIKeys: [LLMProviderKind: String]
    private var catalogRequestIDs: [LLMProviderKind: UUID] = [:]

    init() {
        let settings = SettingsStore.shared
        let routes = Dictionary(uniqueKeysWithValues: LLMTask.allCases.map {
            ($0, settings.toolPanelProvider(for: $0))
        })
        let drafts = Dictionary(uniqueKeysWithValues: LLMProviderKind.allCases.map {
            ($0, ProviderDraft(provider: $0, settings: settings))
        })
        routeProviders = routes
        credentialProvider = routes[.translation] ?? .gemini
        providerDrafts = drafts
        originalAPIKeys = drafts.mapValues(\.apiKey)
        let model = drafts[routes[.translation] ?? .gemini]?.model(for: .translation) ?? ""
        validationTask = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .grammar : .translation
    }

    func persistProvider(showFeedback: Bool, l10n: L10n, refreshConfiguration: () -> Void) {
        let settings = SettingsStore.shared
        for provider in LLMProviderKind.allCases {
            guard let draft = providerDrafts[provider] else { continue }
            for task in LLMTask.allCases {
                settings.setModel(draft.model(for: task).trimmingCharacters(in: .whitespacesAndNewlines), for: provider, task: task)
            }
            let key = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if key != originalAPIKeys[provider] {
                KeychainStore.shared.setAPIKey(key, for: provider)
            }
        }
        if let custom = providerDrafts[.custom] {
            settings.customBaseURL = custom.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let qwen = providerDrafts[.qwen] {
            settings.qwenBaseURL = qwen.qwenBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let mimo = providerDrafts[.mimo] {
            settings.mimoCluster = mimo.mimoCluster
            MiMoService.shared.setCluster(mimo.mimoCluster)
        }
        for task in LLMTask.allCases {
            settings.setToolPanelProvider(routeProviders[task] ?? .gemini, for: task)
        }
        originalAPIKeys = providerDrafts.mapValues { $0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
        refreshConfiguration()
        for provider in Set(routeProviders.values) {
            ensureModelsLoaded(for: provider, l10n: l10n)
        }
        if showFeedback {
            saveMessage = l10n.t("settings.provider.saved")
            validationMessage = nil
        }
    }

    func validateProvider(l10n: L10n, refreshConfiguration: () -> Void) {
        persistProvider(showFeedback: false, l10n: l10n, refreshConfiguration: refreshConfiguration)
        isValidating = true
        validationMessage = nil
        validationSucceeded = false
        saveMessage = nil
        let task = validationTask
        let provider = routeProviders[task] ?? .gemini
        Task { @MainActor in
            do {
                let resolved = try ProviderResolver.resolve(provider, task: task)
                let endpoint = try await resolved.service.validate(apiKey: resolved.apiKey, model: resolved.model)
                self.validationMessage = l10n.t("provider.connected", endpoint)
                self.validationSucceeded = true
            } catch {
                self.validationMessage = l10n.errorText(error)
                self.validationSucceeded = false
            }
            self.isValidating = false
        }
    }

    func ensureModelsLoaded(for provider: LLMProviderKind, l10n: L10n) {
        switch modelCatalogs[provider] {
        case .loading, .loaded: return
        default: refreshModels(for: provider, l10n: l10n)
        }
    }

    func refreshModels(for provider: LLMProviderKind, l10n: L10n) {
        let requestID = UUID()
        catalogRequestIDs[provider] = requestID
        let key = providerDrafts[provider]?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            modelCatalogs[provider] = .failed(l10n.t("settings.provider.modelsNeedKey"))
            return
        }
        modelCatalogs[provider] = .loading
        let service = catalogService(for: provider)
        Task { @MainActor in
            do {
                let models = try await service.listModels(apiKey: key)
                guard self.catalogRequestIDs[provider] == requestID else { return }
                self.modelCatalogs[provider] = .loaded(self.normalizeModels(models))
            } catch {
                guard self.catalogRequestIDs[provider] == requestID else { return }
                self.modelCatalogs[provider] = .failed(l10n.errorText(error))
            }
        }
    }

    private func catalogService(for provider: LLMProviderKind) -> any LLMServicing {
        let draft = providerDrafts[provider]!
        switch provider {
        case .gemini: return GeminiService()
        case .deepseek: return DeepSeekService()
        case .mimo:
            let service = MiMoService()
            service.setCluster(draft.mimoCluster)
            return service
        case .qwen:
            let service = QwenService()
            let base = draft.qwenBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            service.baseURLProvider = { base.isEmpty ? QwenService.defaultBaseURL : base }
            return service
        case .custom:
            let service = CustomService()
            let base = draft.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            service.baseURLProvider = { base }
            return service
        }
    }

    func normalizeModels(_ models: [LLMModel]) -> [LLMModel] {
        var seen = Set<String>()
        return models.compactMap { model in
            let id = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return LLMModel(id: id, displayName: model.displayName, description: model.description)
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    func invalidateModelCatalog(for provider: LLMProviderKind) {
        catalogRequestIDs[provider] = UUID()
        modelCatalogs[provider] = .idle
    }
}
