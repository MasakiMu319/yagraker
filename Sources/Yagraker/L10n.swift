import Foundation
import SwiftUI
import YagrakerCore

/// Runtime-switchable localization. Reads from the SPM resource bundle's .lproj tables,
/// posts `yagrakerLanguageChanged` so AppKit menus/windows can rebuild.
@MainActor
final class L10n: ObservableObject {
    static let shared = L10n()
    static let languageChangedNotification = Notification.Name("yagrakerLanguageChanged")

    @Published var language: AppLanguage {
        didSet {
            SettingsStore.shared.appLanguage = language
            NotificationCenter.default.post(name: Self.languageChangedNotification, object: nil)
        }
    }

    private var bundleCache: [String: Bundle] = [:]

    private init() {
        language = SettingsStore.shared.appLanguage
    }

    /// Concrete language the user reads; also selects prompt wording.
    var reader: ReaderLanguage { language.resolved() }

    var effectiveCode: String { reader.rawValue }

    private func bundle(for code: String) -> Bundle {
        if let cached = bundleCache[code] { return cached }
        let bundle = Bundle.module.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.module
        bundleCache[code] = bundle
        return bundle
    }

    func t(_ key: String) -> String {
        let value = bundle(for: effectiveCode).localizedString(forKey: key, value: nil, table: nil)
        if value == key { // fall back to English table
            return bundle(for: "en").localizedString(forKey: key, value: key, table: nil)
        }
        return value
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    /// Render an LLMError via the localized error tables.
    func errorText(_ error: Error) -> String {
        guard let llmError = error as? LLMError else { return error.localizedDescription }
        switch llmError {
        case .noProvider: return t("error.noProvider")
        case .noAPIKey: return t("error.noAPIKey")
        case .modelEmpty: return t("error.modelEmpty")
        case .modelUnsupported(let task, let model):
            let taskName = switch task {
            case .translation: t("settings.provider.task.translation")
            case .deepRead: t("settings.provider.task.deepRead")
            case .grammar: t("settings.provider.task.grammar")
            }
            return t("error.modelUnsupported", model, taskName)
        case .baseURLEmpty: return t("error.baseURLEmpty")
        case .invalidBaseURL(let url): return t("error.invalidBaseURL", url)
        case .apiError(let msg): return t("error.apiError", msg)
        case .networkError(let msg): return t("error.networkError", msg)
        case .invalidResponse: return t("error.invalidResponse")
        }
    }
}
