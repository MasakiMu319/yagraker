import Foundation

/// Xiaomi MiMo Token Plan — OpenAI-compatible, three regional clusters,
/// and uses `max_completion_tokens` instead of `max_tokens`.
public final class MiMoService: OpenAICompatibleService, @unchecked Sendable {
    public static let shared = MiMoService()

    private let lock = NSLock()
    private var _cluster: MiMoCluster = .cn

    public var cluster: MiMoCluster {
        lock.lock(); defer { lock.unlock() }
        return _cluster
    }

    public init(session: URLSession = .shared) {
        super.init(providerName: "MiMo", session: session)
    }

    public func setCluster(_ cluster: MiMoCluster) {
        lock.lock()
        _cluster = cluster
        lock.unlock()
    }

    public override var maxCompletionTokens: Int? { 4096 }

    public override func endpoint() throws -> URL {
        URL(string: cluster.baseURL + "/chat/completions")!
    }

    public static func isTextGenerationModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let components = normalized.split(separator: "-")
        return !components.contains { component in
            component == "asr" || component == "tts"
        }
    }
}
