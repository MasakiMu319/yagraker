import Foundation
import YagrakerCore

/// Resolves a provider and task into a service, API key, and task-specific model.
enum ProviderResolver {
    struct Resolved {
        let kind: LLMProviderKind
        let task: LLMTask
        let apiKey: String
        let model: String
        let service: any LLMServicing
    }

    static func resolve(_ kind: LLMProviderKind, task: LLMTask) throws -> Resolved {
        let settings = SettingsStore.shared
        guard let storedAPIKey = KeychainStore.shared.apiKey(for: kind) else {
            throw LLMError.noAPIKey
        }
        let apiKey = storedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw LLMError.noAPIKey }
        let model = settings.model(for: kind, task: task).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw LLMError.modelEmpty }
        if kind == .qwen, task != .translation,
           QwenService.isMachineTranslationModel(model) {
            throw LLMError.modelUnsupported(task: task, model: model)
        }
        try configureService(kind, settings: settings)
        let service = LLMServiceFactory.service(for: kind)
        return Resolved(kind: kind, task: task, apiKey: apiKey, model: model, service: service)
    }

    private static func configureService(_ kind: LLMProviderKind, settings: SettingsStore) throws {
        switch kind {
        case .custom:
            CustomService.shared.baseURLProvider = { settings.customBaseURL }
            _ = try CustomService.shared.endpoint()
        case .qwen:
            QwenService.shared.baseURLProvider = { settings.qwenBaseURL }
            _ = try QwenService.shared.endpoint()
        case .mimo:
            MiMoService.shared.setCluster(settings.mimoCluster)
        case .gemini, .deepseek:
            break
        }
    }

    static func configuredProviders(for task: LLMTask) -> [LLMProviderKind] {
        LLMProviderKind.allCases.filter { SettingsStore.shared.isConfigured($0, for: task) }
    }
}
