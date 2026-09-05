import Foundation

/// Google Gemini — `v1beta/models/{model}:generateContent` / `:streamGenerateContent?alt=sse`.
/// Grammar check uses structured output (`responseMimeType: application/json` + `responseSchema`).
public final class GeminiService: LLMServicing, @unchecked Sendable {
    public static let shared = GeminiService()

    let session: URLSession
    private let apiBase = "https://generativelanguage.googleapis.com/v1beta/models"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Request building

    private func url(model: String, method: String, apiKey: String, streaming: Bool = false) throws -> URL {
        guard var components = URLComponents(string: apiBase) else { throw LLMError.invalidResponse }
        components.path += "/\(model):\(method)"
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        if streaming { components.queryItems?.append(URLQueryItem(name: "alt", value: "sse")) }
        guard let url = components.url else { throw LLMError.invalidResponse }
        return url
    }

    private func makeRequest(url: URL, body: [String: Any], timeout: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func contentsBody(system: String, user: String, generationConfig: [String: Any]? = nil) -> [String: Any] {
        var body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": user]]]
            ],
        ]
        if !system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }
        if let generationConfig {
            body["generationConfig"] = generationConfig
        }
        return body
    }

    // MARK: Schemas

    static let grammarResponseSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "corrections": [
                "type": "ARRAY",
                "description": "One entry per independent mistake, in document order; empty when nothing needs correction.",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "original": [
                            "type": "STRING",
                            "description": "Exact contiguous substring of the submission that occurs only once in it.",
                        ],
                        "corrected": [
                            "type": "STRING",
                            "description": "Non-empty replacement for the span.",
                        ],
                        "explanation": [
                            "type": "STRING",
                            "description": "Brief explanation in the reader's language of why this was changed.",
                        ],
                    ],
                    "required": ["original", "corrected"],
                ],
            ],
            "tip": [
                "type": "STRING",
                "description": "One to three plain-text sentences in the reader's language; empty when there are no corrections.",
            ],
        ],
        "required": ["corrections", "tip"],
    ]

    // MARK: LLMServicing

    public func checkGrammar(request: GrammarCheckRequest, apiKey: String, model: String) async throws -> CorrectionResult {
        let userPrompt = Prompts.grammarUserPrompt(text: request.text)
        let body = contentsBody(
            system: Prompts.grammarSystem(for: request.reader),
            user: userPrompt,
            generationConfig: [
                "responseMimeType": "application/json",
                "responseSchema": Self.grammarResponseSchema,
            ]
        )
        let streamingRequest = try makeRequest(
            url: try url(model: model, method: "streamGenerateContent", apiKey: apiKey, streaming: true),
            body: body,
            timeout: 300
        )
        let content: String
        do {
            content = try await postStreaming(streamingRequest)
        } catch {
            guard shouldRetryWithoutStreaming(error) else { throw error }
            let fallbackRequest = try makeRequest(
                url: try url(model: model, method: "generateContent", apiKey: apiKey),
                body: body,
                timeout: 300
            )
            content = try await post(fallbackRequest)
        }
        return try LLMParsing.decode(CorrectionResult.self, from: content, label: "JSON")
    }

    public func streamText(
        task: LLMTask,
        text: String,
        systemPrompt: String,
        targetLanguage: TranslationTargetLanguage,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        do {
            let body = contentsBody(system: systemPrompt, user: Prompts.userPrompt(task: task, text: text))
            let request = try makeRequest(
                url: try url(model: model, method: "streamGenerateContent", apiKey: apiKey, streaming: true),
                body: body, timeout: 300
            )
            let payloads = session.sseDataLines(for: request)
            return mapSSEPayloads(payloads) { data in
                LLMParsing.geminiStreamDelta(from: data)
            }
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    public func listModels(apiKey: String) async throws -> [LLMModel] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.noAPIKey
        }
        var models: [LLMModel] = []
        var pageToken: String?
        var pageCount = 0

        repeat {
            guard var components = URLComponents(string: apiBase) else {
                throw LLMError.invalidResponse
            }
            var queryItems = [URLQueryItem(name: "key", value: apiKey)]
            if let pageToken, !pageToken.isEmpty {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems
            guard let requestURL = components.url else { throw LLMError.invalidResponse }

            var request = URLRequest(url: requestURL, timeoutInterval: 30)
            request.httpMethod = "GET"
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw LLMError.networkError(error.localizedDescription)
            }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = root["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw LLMError.apiError(message)
                }
                throw LLMError.apiError("HTTP \(http.statusCode)")
            }

            models.append(contentsOf: try LLMParsing.geminiModels(from: data))
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            pageToken = root?["nextPageToken"] as? String
            pageCount += 1
        } while pageToken?.isEmpty == false && pageCount < 20

        var seen = Set<String>()
        return models
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public func validate(apiKey: String, model: String) async throws -> String {
        let body = contentsBody(system: "", user: Prompts.validationProbe)
        let request = try makeRequest(url: try url(model: model, method: "generateContent", apiKey: apiKey), body: body, timeout: 30)
        _ = try await post(request)
        return "\(apiBase)/\(model)"
    }

    private func postStreaming(_ request: URLRequest) async throws -> String {
        var content = ""
        for try await payload in session.sseDataLines(for: request) {
            guard let data = payload.data(using: .utf8),
                  let delta = LLMParsing.geminiStreamDelta(from: data) else { continue }
            content += delta
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidResponse
        }
        return content
    }

    private func shouldRetryWithoutStreaming(_ error: Error) -> Bool {
        guard let error = error as? LLMError else { return false }
        switch error {
        case .apiError, .invalidResponse:
            return true
        default:
            return false
        }
    }

    // MARK: HTTP

    private func post(_ request: URLRequest) async throws -> String {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LLMError.networkError(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = root["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw LLMError.apiError(message)
            }
            throw LLMError.apiError("HTTP \(http.statusCode)")
        }
        return try LLMParsing.geminiContent(from: data)
    }
}
