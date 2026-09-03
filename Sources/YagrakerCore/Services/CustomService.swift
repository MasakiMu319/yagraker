import Foundation

/// Any OpenAI-compatible endpoint: user-configured Base URL + `POST {base}/chat/completions`.
/// Sends no `temperature`, no `max_tokens` (gpt-5 / o-series / Kimi reject them).
public final class CustomService: OpenAICompatibleService, @unchecked Sendable {
    public static let shared = CustomService()

    /// Base URL provider, injected so the app layer owns persistence.
    public var baseURLProvider: () -> String = { "" }

    public init(session: URLSession = .shared) {
        super.init(providerName: "Custom", session: session)
    }

    public override func endpoint() throws -> URL {
        let base = baseURLProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw LLMError.baseURLEmpty }
        guard let url = URL(string: base),
              url.query == nil,
              url.fragment == nil,
              let scheme = url.scheme?.lowercased(),
              let host = url.host,
              scheme == "https" || (scheme == "http" && Self.isLocalHost(host)) else {
            throw LLMError.invalidBaseURL(base)
        }
        return url.appendingPathComponent("chat/completions")
    }

    /// Plain HTTP is accepted only for loopback/private development endpoints.
    public static func isLocalHost(_ host: String) -> Bool {
        let normalized = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        if normalized == "localhost" || normalized.hasSuffix(".localhost")
            || normalized == "::1" || normalized == "0.0.0.0"
            || normalized.hasSuffix(".local") {
            return true
        }
        let octets = normalized.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ 0...255 ~= $0 }) else { return false }
        return octets[0] == 10 || octets[0] == 127
            || (octets[0] == 172 && 16...31 ~= octets[1])
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 169 && octets[1] == 254)
}
}
