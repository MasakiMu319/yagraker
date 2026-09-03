import Foundation

// MARK: - Service protocol

public protocol LLMServicing: Sendable {
    func checkGrammar(request: GrammarCheckRequest, apiKey: String, model: String) async throws -> CorrectionResult
    /// `targetLanguage` is consumed by machine-translation endpoints; chat
    /// providers already carry it inside `systemPrompt`.
    func streamText(
        task: LLMTask,
        text: String,
        systemPrompt: String,
        targetLanguage: TranslationTargetLanguage,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error>
    /// Return the models advertised by the provider's official model-list endpoint.
    func listModels(apiKey: String) async throws -> [LLMModel]
    /// Minimal provider round-trip. Returns a human-readable endpoint label on success.
    func validate(apiKey: String, model: String) async throws -> String
}

public enum LLMServiceFactory {
    public static func service(for kind: LLMProviderKind) -> any LLMServicing {
        switch kind {
        case .deepseek: return DeepSeekService.shared
        case .gemini: return GeminiService.shared
        case .qwen: return QwenService.shared
        case .mimo: return MiMoService.shared
        case .custom: return CustomService.shared
        }
    }
}

// MARK: - Response parsing helpers

public enum LLMParsing {

    /// A page returned by Alibaba Cloud Model Studio's model catalog.
    struct QwenModelPage: Sendable {
        let models: [LLMModel]
        let total: Int?
        let pageNumber: Int?
        let pageSize: Int?
    }

    /// Extract the assistant text from an OpenAI chat-completions envelope.
    public static func openAIMessageContent(from data: Data, provider: String) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }
        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(message)
        }
        guard let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }
        return content
    }

    /// Extract model identifiers from an OpenAI-compatible `/models` envelope.
    public static func openAIModels(from data: Data, provider: String) throws -> [LLMModel] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }
        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(message)
        }
        guard let entries = root["data"] as? [[String: Any]] else {
            throw LLMError.invalidResponse
        }
        return entries.compactMap { entry in
            guard let id = entry["id"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let displayName = (entry["name"] as? String) ?? (entry["display_name"] as? String)
            return LLMModel(id: id, displayName: displayName)
        }
    }

    /// Extract a page from Alibaba Cloud Model Studio's `GET /api/v1/models` response.
    static func qwenModelPage(from data: Data) throws -> QwenModelPage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }
        if let success = root["success"] as? Bool, !success {
            let message = (root["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = (root["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LLMError.apiError(message.flatMap { $0.isEmpty ? nil : $0 } ?? code.flatMap { $0.isEmpty ? nil : $0 } ?? "Qwen model catalog request failed")
        }
        if let code = root["code"] as? String,
           !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           code.lowercased() != "null" {
            let message = (root["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LLMError.apiError(message.flatMap { $0.isEmpty ? nil : $0 } ?? code)
        }
        guard let output = root["output"] as? [String: Any],
              let entries = output["models"] as? [[String: Any]] else {
            throw LLMError.invalidResponse
        }

        let models = entries.compactMap { entry -> LLMModel? in
            let rawID = (entry["model"] as? String) ?? (entry["id"] as? String)
            guard let rawID else { return nil }
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            let displayName = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = (entry["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return LLMModel(
                id: id,
                displayName: displayName?.isEmpty == false ? displayName : nil,
                description: description?.isEmpty == false ? description : nil
            )
        }

        func integer(_ value: Any?) -> Int? {
            if let value = value as? Int { return value }
            if let value = value as? NSNumber { return value.intValue }
            if let value = value as? String { return Int(value) }
            return nil
        }

        return QwenModelPage(
            models: models,
            total: integer(output["total"]),
            pageNumber: integer(output["page_no"]),
            pageSize: integer(output["page_size"])
        )
    }

    /// Extract the model text from a Gemini generateContent envelope.
    public static func geminiContent(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }
        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown Gemini error"
            throw LLMError.apiError(message)
        }
        guard let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw LLMError.invalidResponse
        }
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    /// Extract text-generation models from a Gemini `models.list` response.
    public static func geminiModels(from data: Data) throws -> [LLMModel] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }
        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown Gemini error"
            throw LLMError.apiError(message)
        }
        guard let entries = root["models"] as? [[String: Any]] else {
            throw LLMError.invalidResponse
        }
        return entries.compactMap { entry in
            guard let rawName = entry["name"] as? String else { return nil }
            let id = rawName.hasPrefix("models/") ? String(rawName.dropFirst("models/".count)) : rawName
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let methods = entry["supportedGenerationMethods"] as? [String] ?? []
            guard methods.contains("generateContent") || methods.contains("streamGenerateContent") else {
                return nil
            }
            let displayName = (entry["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = (entry["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return LLMModel(
                id: id,
                displayName: displayName?.isEmpty == false ? displayName : nil,
                description: description?.isEmpty == false ? description : nil
            )
        }
    }

    /// Strip a leading/trailing ```json fence and any prose outside the first/last brace.
    public static func stripCodeFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            if let newline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: newline)...])
            }
            if result.hasSuffix("```") {
                result = String(result.dropLast(3))
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Drop surrounding prose: keep the outermost brace/bracket span.
        if let open = result.firstIndex(where: { $0 == "{" || $0 == "[" }),
           let close = result.lastIndex(where: { $0 == "}" || $0 == "]" }), open < close {
            result = String(result[open...close])
        }
        return result
    }

    /// Lenient JSON decode: JSON5-tolerant, fence-stripping, prose-trimming.
    public static func decode<T: Decodable>(_ type: T.Type, from text: String, label: String) throws -> T {
        let cleaned = stripCodeFences(text)
        guard let data = cleaned.data(using: .utf8) else { throw LLMError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LLMError.invalidResponse
        }
    }

    /// Extract `delta.content` fragments from an OpenAI-style SSE payload line.
    public static func openAIStreamDelta(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else { return nil }
        return delta["content"] as? String
    }

    /// Extract `candidates[0].content.parts[].text` from a Gemini streamGenerateContent SSE payload.
    public static func geminiStreamDelta(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return nil }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }
}

// MARK: - SSE helper

extension URLSession {
    /// Parse an SSE byte stream, yielding the raw `data:` payload strings.
    func sseDataLines(for request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await self.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 4000 { break } }
                        if let data = body.data(using: .utf8),
                           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = root["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            continuation.finish(throwing: LLMError.apiError(message))
                        } else {
                            continuation.finish(throwing: LLMError.apiError("HTTP \(http.statusCode)"))
                        }
                        return
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        if !payload.isEmpty { continuation.yield(payload) }
                    }
                    continuation.finish()
                } catch {
                    if error is CancellationError || (error as? URLError)?.code == .cancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: LLMError.networkError(error.localizedDescription))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - OpenAI-compatible base

/// Shared implementation for DeepSeek / MiMo / Custom providers.
/// Faithful quirks: no `temperature` anywhere; no `max_tokens`; MiMo sends `max_completion_tokens`.
public class OpenAICompatibleService: LLMServicing, @unchecked Sendable {

    public let providerName: String
    /// MiMo requires `max_completion_tokens`; others get none.
    public var maxCompletionTokens: Int? { nil }
    let session: URLSession

    public init(providerName: String, session: URLSession = .shared) {
        self.providerName = providerName
        self.session = session
    }

    /// Full chat/completions URL. Overridden by subclasses.
    public func endpoint() throws -> URL { throw LLMError.invalidBaseURL(providerName) }

    /// URL for the provider's OpenAI-compatible model catalog.
    public func modelsEndpoint() throws -> URL {
        var url = try endpoint()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url.appendingPathComponent("models")
    }

    // MARK: Requests

    func makeRequest(body: [String: Any], apiKey: String, timeout: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: try endpoint(), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Non-streaming chat completion → assistant content string.
    func postChatCompletion(body: [String: Any], apiKey: String, timeout: TimeInterval) async throws -> String {
        let request = try makeRequest(body: body, apiKey: apiKey, timeout: timeout)
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
        return try LLMParsing.openAIMessageContent(from: data, provider: providerName)
    }

    /// Streaming chat completion, accumulated for structured JSON responses.
    /// Streaming keeps long generations alive while preserving the same final parse step.
    func streamChatCompletion(body: [String: Any], apiKey: String, timeout: TimeInterval) async throws -> String {
        let request = try makeRequest(body: body, apiKey: apiKey, timeout: timeout)
        var content = ""
        for try await payload in session.sseDataLines(for: request) {
            guard let data = payload.data(using: .utf8),
                  let delta = LLMParsing.openAIStreamDelta(from: data) else { continue }
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

    func messagesBody(system: String, user: String, model: String, stream: Bool, jsonMode: Bool) -> [String: Any] {
        var messages: [[String: String]] = []
        if !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": user])
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": stream,
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        if let maxCompletionTokens {
            body["max_completion_tokens"] = maxCompletionTokens
        }
        return body
    }

    // MARK: LLMServicing

    public func checkGrammar(request: GrammarCheckRequest, apiKey: String, model: String) async throws -> CorrectionResult {
        let systemPrompt = Prompts.grammarSystem(for: request.reader)
        let userPrompt = Prompts.grammarUserPrompt(text: request.text)
        let streamingBody = messagesBody(system: systemPrompt, user: userPrompt, model: model, stream: true, jsonMode: true)
        let content: String
        do {
            content = try await streamChatCompletion(body: streamingBody, apiKey: apiKey, timeout: 300)
        } catch {
            guard shouldRetryWithoutStreaming(error) else { throw error }
            let fallbackBody = messagesBody(system: systemPrompt, user: userPrompt, model: model, stream: false, jsonMode: true)
            content = try await postChatCompletion(body: fallbackBody, apiKey: apiKey, timeout: 300)
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
            let body = messagesBody(system: systemPrompt, user: Prompts.userPrompt(task: task, text: text), model: model, stream: true, jsonMode: false)
            let request = try makeRequest(body: body, apiKey: apiKey, timeout: 300)
            let payloads = session.sseDataLines(for: request)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await payload in payloads {
                            guard let data = payload.data(using: .utf8) else { continue }
                            if let delta = LLMParsing.openAIStreamDelta(from: data), !delta.isEmpty {
                                continuation.yield(delta)
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    public func listModels(apiKey: String) async throws -> [LLMModel] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.noAPIKey
        }
        var request = URLRequest(url: try modelsEndpoint(), timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        return try LLMParsing.openAIModels(from: data, provider: providerName)
    }

    public func validate(apiKey: String, model: String) async throws -> String {
        let body = messagesBody(system: "", user: Prompts.validationProbe, model: model, stream: false, jsonMode: false)
        _ = try await postChatCompletion(body: body, apiKey: apiKey, timeout: 30)
        return try endpoint().absoluteString
    }
}
