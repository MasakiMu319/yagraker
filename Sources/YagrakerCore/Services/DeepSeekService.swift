import Foundation

/// DeepSeek — hardcoded `https://api.deepseek.com/chat/completions` (no `/v1`).
public final class DeepSeekService: OpenAICompatibleService, @unchecked Sendable {
    public static let shared = DeepSeekService()

    public init(session: URLSession = .shared) {
        super.init(providerName: "DeepSeek", session: session)
    }

    public override func endpoint() throws -> URL {
        URL(string: "https://api.deepseek.com/chat/completions")!
    }
}
