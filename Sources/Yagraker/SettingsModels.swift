import Foundation
import YagrakerCore

struct ProviderDraft: Equatable, Sendable {
    var models: [LLMTask: String]
    var apiKey: String
    var customBaseURL: String
    var qwenBaseURL: String
    var mimoCluster: MiMoCluster

    init(provider: LLMProviderKind, settings: SettingsStore) {
        models = Dictionary(uniqueKeysWithValues: LLMTask.allCases.map {
            ($0, settings.model(for: provider, task: $0))
        })
        apiKey = KeychainStore.shared.apiKey(for: provider) ?? ""
        customBaseURL = settings.customBaseURL
        qwenBaseURL = settings.qwenBaseURL
        mimoCluster = settings.mimoCluster
    }

    func model(for task: LLMTask) -> String {
        models[task] ?? ""
    }

    mutating func setModel(_ model: String, for task: LLMTask) {
        models[task] = model
    }
}

struct ModelCatalogInput: Equatable {
    let apiKey: String
    let customBaseURL: String
    let qwenBaseURL: String
    let mimoCluster: MiMoCluster
}

enum ModelCatalogState: Equatable {
    case idle
    case loading
    case loaded([LLMModel])
    case failed(String)
}
