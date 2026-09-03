import Foundation

public final class QwenService: OpenAICompatibleService, @unchecked Sendable {
    public static let shared = QwenService()
    public static let defaultBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    public static let supportedTranslationModels = QwenTranslationModel.allCases

    public var baseURLProvider: () -> String = { QwenService.defaultBaseURL }

    public init(session: URLSession = .shared) {
        super.init(providerName: "Qwen", session: session)
    }

    public override func endpoint() throws -> URL {
        let base = baseURLProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidBaseURL(base), let url = URL(string: base) else {
            throw LLMError.invalidBaseURL(base)
        }
        return url.appendingPathComponent("chat/completions")
    }

    /// Alibaba Cloud's official model catalog is served from `/api/v1/models`,
    /// rather than the OpenAI-compatible `/compatible-mode/v1/models` path.
    public override func modelsEndpoint() throws -> URL {
        let base = baseURLProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidBaseURL(base), var components = URLComponents(string: base) else {
            throw LLMError.invalidBaseURL(base)
        }
        components.path = "/api/v1/models"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw LLMError.invalidBaseURL(base) }
        return url
    }

    public static func isValidBaseURL(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              url.host != nil,
              url.query == nil,
              url.fragment == nil,
              scheme == "https" else { return false }
        return true
    }

    public override func checkGrammar(
        request: GrammarCheckRequest,
        apiKey: String,
        model: String
    ) async throws -> CorrectionResult {
        guard !Self.isMachineTranslationModel(model) else {
            throw LLMError.modelUnsupported(task: .grammar, model: model)
        }
        return try await super.checkGrammar(request: request, apiKey: apiKey, model: model)
    }

    public override func streamText(
        task: LLMTask,
        text: String,
        systemPrompt: String,
        targetLanguage: TranslationTargetLanguage,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        if task != .translation, Self.isMachineTranslationModel(model) {
            return AsyncThrowingStream {
                $0.finish(throwing: LLMError.modelUnsupported(task: task, model: model))
            }
        }

        guard Self.isMachineTranslationModel(model) else {
            return super.streamText(
                task: task,
                text: text,
                systemPrompt: systemPrompt,
                targetLanguage: targetLanguage,
                apiKey: apiKey,
                model: model
            )
        }

        if Self.supportsIncrementalStreaming(model) {
            return incrementalTranslationStream(
                text: text,
                targetLanguage: targetLanguage,
                apiKey: apiKey,
                model: model
            )
        }

        return oneShotTranslationStream(
            text: text,
            targetLanguage: targetLanguage,
            apiKey: apiKey,
            model: model
        )
    }

    public override func validate(apiKey: String, model: String) async throws -> String {
        if Self.isMachineTranslationModel(model) {
            _ = try await postTranslation(text: "Hello", apiKey: apiKey, model: model, targetLanguage: .simplifiedChinese)
        } else {
            _ = try await super.validate(apiKey: apiKey, model: model)
        }
        return try endpoint().absoluteString
    }

    public override func listModels(apiKey: String) async throws -> [LLMModel] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.noAPIKey
        }

        let requestedPageSize = 100
        var pageNumber = 1
        var collected: [LLMModel] = []
        var total: Int?

        while pageNumber <= 100 {
            var components = URLComponents(url: try modelsEndpoint(), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "providers", value: "qwen"),
                URLQueryItem(name: "capabilities", value: "TG"),
                URLQueryItem(name: "page_no", value: String(pageNumber)),
                URLQueryItem(name: "page_size", value: String(requestedPageSize)),
            ]
            guard let requestURL = components?.url else { throw LLMError.invalidResponse }

            var request = URLRequest(url: requestURL, timeoutInterval: 30)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw LLMError.networkError(error.localizedDescription)
            }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = (root["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !message.isEmpty {
                    throw LLMError.apiError(message)
                }
                throw LLMError.apiError("HTTP \(http.statusCode)")
            }

            let page = try LLMParsing.qwenModelPage(from: data)
            collected.append(contentsOf: page.models)
            total = page.total ?? total
            let effectivePageSize = max(page.pageSize ?? requestedPageSize, 1)
            if page.models.isEmpty { break }
            if let total, collected.count >= total { break }
            if page.total == nil && page.models.count < effectivePageSize { break }
            pageNumber += 1
        }

        var seen = Set<String>()
        var merged = collected.filter { seen.insert($0.id).inserted }

        // The catalog request filters to text-generation capability, so Qwen-MT
        // machine-translation models are never advertised. Merge in the known
        // built-in set so the translation picker always offers them.
        for model in Self.supportedTranslationModels where seen.insert(model.rawValue).inserted {
            merged.append(LLMModel(id: model.rawValue))
        }

        return merged
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private func postTranslation(
        text: String,
        apiKey: String,
        model: String,
        targetLanguage: TranslationTargetLanguage
    ) async throws -> String {
        try await postChatCompletion(
            body: translationBody(
                text: text,
                model: model,
                stream: false,
                targetLanguage: targetLanguage
            ),
            apiKey: apiKey,
            timeout: 300
        )
    }

    private func translationBody(
        text: String,
        model: String,
        stream: Bool,
        targetLanguage: TranslationTargetLanguage
    ) -> [String: Any] {
        [
            "model": model,
            "messages": [["role": "user", "content": text]],
            "stream": stream,
            "translation_options": [
                "source_lang": "auto",
                "target_lang": targetLanguage.rawValue,
            ],
        ]
    }

    public static func isMachineTranslationModel(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("qwen-mt-")
    }

    public static func supportsIncrementalStreaming(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let knownModel = QwenTranslationModel(rawValue: normalized) {
            return knownModel.supportsIncrementalStreaming
        }
        return normalized.hasPrefix("qwen-mt-flash-") || normalized.hasPrefix("qwen-mt-lite-")
    }

    private func incrementalTranslationStream(
        text: String,
        targetLanguage: TranslationTargetLanguage,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        do {
            let body = translationBody(
                text: text,
                model: model,
                stream: true,
                targetLanguage: targetLanguage
            )
            let request = try makeRequest(body: body, apiKey: apiKey, timeout: 300)
            let payloads = session.sseDataLines(for: request)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    var yieldedContent = false
                    do {
                        for try await payload in payloads {
                            guard let data = payload.data(using: .utf8),
                                  let delta = LLMParsing.openAIStreamDelta(from: data),
                                  !delta.isEmpty else { continue }
                            yieldedContent = true
                            continuation.yield(delta)
                        }
                        guard yieldedContent else { throw LLMError.invalidResponse }
                        continuation.finish()
                    } catch {
                        guard !yieldedContent,
                              Self.shouldRetryWithoutStreaming(error),
                              !Task.isCancelled else {
                            continuation.finish(throwing: error)
                            return
                        }
                        do {
                            let content = try await self.postTranslation(
                                text: text,
                                apiKey: apiKey,
                                model: model,
                                targetLanguage: targetLanguage
                            )
                            continuation.yield(content)
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    private func oneShotTranslationStream(
        text: String,
        targetLanguage: TranslationTargetLanguage,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let content = try await self.postTranslation(
                        text: text,
                        apiKey: apiKey,
                        model: model,
                        targetLanguage: targetLanguage
                    )
                    continuation.yield(content)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func shouldRetryWithoutStreaming(_ error: Error) -> Bool {
        guard let error = error as? LLMError else { return false }
        switch error {
        case .apiError, .invalidResponse:
            return true
        default:
            return false
        }
    }
}
