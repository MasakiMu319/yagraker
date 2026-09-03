import Foundation
import Security

/// All provider API keys live in a single generic-password item:
/// service `com.yagraker.app`, account `llm_api_keys`, value = JSON `{provider: key}`.
public final class KeychainStore: Sendable {
    public static let shared = KeychainStore()

    private let service = "com.yagraker.app"
    private let account = "llm_api_keys"
    private let lock = NSLock()

    public init() {}

    public func apiKey(for provider: LLMProviderKind) -> String? {
        readAll()[provider.rawValue]
    }

    public func setAPIKey(_ key: String?, for provider: LLMProviderKind) {
        lock.lock()
        var map = readAll()
        if let key, !key.isEmpty {
            map[provider.rawValue] = key
        } else {
            map.removeValue(forKey: provider.rawValue)
        }
        if map.isEmpty {
            deleteItem()
        } else {
            let data = try? JSONSerialization.data(withJSONObject: map, options: [.sortedKeys])
            if let data { writeItem(data) }
        }
        lock.unlock()
    }

    // MARK: - Keychain primitives

    private func readAll() -> [String: String] {
        guard let data = readItem(),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return map
    }

    private func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readItem() -> Data? {
        var query = query()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func writeItem(_ data: Data) {
        if readItem() != nil {
            _ = SecItemUpdate(query() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var item = query()
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            _ = SecItemAdd(item as CFDictionary, nil)
        }
    }

    private func deleteItem() {
        SecItemDelete(query() as CFDictionary)
    }
}

/// UserDefaults-backed application settings.
public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()

    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Provider

    public var mimoCluster: MiMoCluster {
        get { MiMoCluster(rawValue: defaults.string(forKey: "provider.mimo.cluster") ?? "") ?? .cn }
        set { defaults.set(newValue.rawValue, forKey: "provider.mimo.cluster") }
    }

    public func model(for provider: LLMProviderKind, task: LLMTask) -> String {
        let stored = defaults.string(forKey: provider.modelDefaultsKey(for: task)) ?? ""
        return stored.isEmpty ? provider.defaultModel(for: task) : stored
    }

    public func setModel(_ model: String, for provider: LLMProviderKind, task: LLMTask) {
        defaults.set(model, forKey: provider.modelDefaultsKey(for: task))
    }

    public var customBaseURL: String {
        get { defaults.string(forKey: "provider.custom.baseURL") ?? "" }
        set { defaults.set(newValue, forKey: "provider.custom.baseURL") }
    }

    public var qwenBaseURL: String {
        get {
            let stored = defaults.string(forKey: "provider.qwen.baseURL") ?? ""
            return stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? QwenService.defaultBaseURL
                : stored
        }
        set { defaults.set(newValue, forKey: "provider.qwen.baseURL") }
    }

    // MARK: Task routing and panel

    public func toolPanelProvider(for task: LLMTask) -> LLMProviderKind {
        LLMProviderKind(rawValue: defaults.string(forKey: "panel.\(task.rawValue).provider") ?? "") ?? .gemini
    }

    public func setToolPanelProvider(_ provider: LLMProviderKind, for task: LLMTask) {
        defaults.set(provider.rawValue, forKey: "panel.\(task.rawValue).provider")
    }

    public var isPinned: Bool {
        get { defaults.bool(forKey: "panel.pinned") }
        set { defaults.set(newValue, forKey: "panel.pinned") }
    }

    public var panelSize: CGSize? {
        get {
            guard defaults.object(forKey: "panel.width") != nil,
                  defaults.object(forKey: "panel.height") != nil else { return nil }
            let width = defaults.double(forKey: "panel.width")
            let height = defaults.double(forKey: "panel.height")
            guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
            return CGSize(width: width, height: height)
        }
        set {
            if let newValue {
                defaults.set(Double(newValue.width), forKey: "panel.width")
                defaults.set(Double(newValue.height), forKey: "panel.height")
            } else {
                defaults.removeObject(forKey: "panel.width")
                defaults.removeObject(forKey: "panel.height")
            }
        }
    }

    public var panelTopLeft: CGPoint? {
        get {
            guard defaults.object(forKey: "panel.topLeft.x") != nil else { return nil }
            return CGPoint(x: defaults.double(forKey: "panel.topLeft.x"),
                           y: defaults.double(forKey: "panel.topLeft.y"))
        }
        set {
            if let newValue {
                defaults.set(Double(newValue.x), forKey: "panel.topLeft.x")
                defaults.set(Double(newValue.y), forKey: "panel.topLeft.y")
            }
        }
    }

    // MARK: Language

    public var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: "app.language") ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "app.language") }
    }

    // MARK: Updates

    public var automaticallyChecksForUpdates: Bool {
        get { defaults.object(forKey: "updates.automaticChecks") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "updates.automaticChecks") }
    }

    public var updatesLastCheckedAt: Date? {
        get { defaults.object(forKey: "updates.lastCheckedAt") as? Date }
        set { defaults.set(newValue, forKey: "updates.lastCheckedAt") }
    }

    public func isConfigured(_ provider: LLMProviderKind, for task: LLMTask) -> Bool {
        guard let key = KeychainStore.shared.apiKey(for: provider),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let model = model(for: provider, task: task).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return false }
        if provider == .qwen, task != .translation, QwenService.isMachineTranslationModel(model) {
            return false
        }
        if provider == .custom {
            let base = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: base),
                  url.query == nil,
                  url.fragment == nil,
                  let scheme = url.scheme?.lowercased(),
                  let host = url.host,
                  scheme == "https" || (scheme == "http" && CustomService.isLocalHost(host)) else { return false }
        }
        if provider == .qwen && !QwenService.isValidBaseURL(qwenBaseURL) { return false }
        return true
    }

    public func isConfigured(_ provider: LLMProviderKind) -> Bool {
        LLMTask.allCases.contains { isConfigured(provider, for: $0) }
    }
}
