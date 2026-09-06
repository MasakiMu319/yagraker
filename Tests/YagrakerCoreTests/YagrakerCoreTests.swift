import XCTest
@testable import YagrakerCore

/// Captures requests and replays canned responses.
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

class ServiceTestCase: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        session = nil
        super.tearDown()
    }

    func stub(_ body: String, status: Int = 200) {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, body.data(using: .utf8)!)
        }
    }

    func lastRequestBody(_ request: URLRequest) -> [String: Any] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                collected.append(buffer, count: count)
            }
            data = collected
        } else {
            data = Data()
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

    func jsonString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        let array = String(data: data, encoding: .utf8)!
        return String(array.dropFirst().dropLast())
    }
}

final class SettingsStoreTests: XCTestCase {
    func testSettingsUseNamespacedStorageKeys() {
        let domain = "YagrakerCoreTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = SettingsStore(defaults: defaults)

        store.mimoCluster = .eu
        store.setModel("model", for: .custom, task: .grammar)
        store.setModel("translate-model", for: .custom, task: .translation)
        store.setModel("deep-read-model", for: .custom, task: .deepRead)
        store.customBaseURL = "https://example.com/v1"
        store.setToolPanelProvider(.mimo, for: .grammar)
        store.setToolPanelProvider(.qwen, for: .translation)
        store.setToolPanelProvider(.deepseek, for: .deepRead)
        store.isPinned = true
        store.panelSize = CGSize(width: 700, height: 420)
        store.panelTopLeft = CGPoint(x: 12, y: 34)
        store.appLanguage = .simplifiedChinese
        store.automaticallyChecksForUpdates = true
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        store.updatesLastCheckedAt = checkedAt

        XCTAssertEqual(defaults.string(forKey: "provider.mimo.cluster"), "eu")
        XCTAssertEqual(defaults.string(forKey: "provider.custom.grammarModel"), "model")
        XCTAssertEqual(defaults.string(forKey: "provider.custom.translationModel"), "translate-model")
        XCTAssertEqual(defaults.string(forKey: "provider.custom.deepReadModel"), "deep-read-model")
        XCTAssertEqual(defaults.string(forKey: "provider.custom.baseURL"), "https://example.com/v1")
        XCTAssertEqual(defaults.string(forKey: "panel.grammar.provider"), "mimo")
        XCTAssertEqual(defaults.string(forKey: "panel.translation.provider"), "qwen")
        XCTAssertEqual(defaults.string(forKey: "panel.deepRead.provider"), "deepseek")
        XCTAssertEqual(store.toolPanelProvider(for: .grammar), .mimo)
        XCTAssertEqual(store.toolPanelProvider(for: .translation), .qwen)
        XCTAssertEqual(store.toolPanelProvider(for: .deepRead), .deepseek)
        XCTAssertTrue(defaults.bool(forKey: "panel.pinned"))
        XCTAssertEqual(store.panelSize, CGSize(width: 700, height: 420))
        XCTAssertEqual(defaults.double(forKey: "panel.width"), 700)
        XCTAssertEqual(defaults.double(forKey: "panel.height"), 420)
        XCTAssertEqual(defaults.double(forKey: "panel.topLeft.x"), 12)
        XCTAssertEqual(defaults.double(forKey: "panel.topLeft.y"), 34)
        XCTAssertEqual(defaults.string(forKey: "app.language"), "zh-Hans")
        XCTAssertTrue(defaults.bool(forKey: "updates.automaticChecks"))
        XCTAssertEqual(defaults.object(forKey: "updates.lastCheckedAt") as? Date, checkedAt)
    }

    func testCorePromptsRemainConfigured() {
        XCTAssertTrue(Prompts.grammarUserPrompt(text: "hello").contains("<text>\nhello\n</text>"))
        XCTAssertTrue(Prompts.translatorSystem(target: .english).contains("into fluent English"))
        XCTAssertTrue(Prompts.deepReadSystem(target: .simplifiedChinese, reader: .simplifiedChinese).contains("## 句子主干"))
        XCTAssertEqual(Prompts.validationProbe, "Respond with only CONNECTED")
    }

    func testPromptsFollowReaderLanguage() {
        XCTAssertTrue(Prompts.grammarSystem(for: .simplifiedChinese).contains("conversational Simplified Chinese"))
        XCTAssertTrue(Prompts.grammarSystem(for: .traditionalChinese).contains("conversational Traditional Chinese"))
        XCTAssertTrue(Prompts.grammarSystem(for: .english).contains("conversational English"))
        XCTAssertFalse(Prompts.grammarSystem(for: .english).contains("corrected_text"))
        XCTAssertTrue(Prompts.translatorSystem(target: .traditionalChinese).contains("into fluent Traditional Chinese"))
        XCTAssertTrue(Prompts.deepReadSystem(target: .english, reader: .traditionalChinese).contains("## 句子主幹"))
        XCTAssertTrue(Prompts.deepReadSystem(target: .simplifiedChinese, reader: .english).contains("## Sentence Core"))
    }

    func testAppLanguageResolution() {
        XCTAssertEqual(AppLanguage.traditionalChinese.resolved(preferredLanguages: ["en-US"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-Hant-TW", "en-US"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-HK"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "en-GB"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["ja-JP"]), .english)
    }

    func testChatUserPromptsWrapSourceText() {
        for task: LLMTask in [.translation, .deepRead] {
            let prompt = Prompts.userPrompt(task: task, text: "hello")
            XCTAssertTrue(prompt.contains("<source>\nhello\n</source>"), "\(task) must wrap source text")
        }
        // Grammar keeps its own <text> scaffold through the same dispatcher.
        XCTAssertTrue(Prompts.userPrompt(task: .grammar, text: "hello").contains("<text>\nhello\n</text>"))
    }
}

final class ParsingTests: XCTestCase {

    func testSharedHTTPErrorMappingHandlesProviderEnvelopeVariants() throws {
        let url = URL(string: "https://example.com")!
        let openAI = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try LLMTransport.throwIfHTTPError(
            data: #"{"error":{"message":"bad key"}}"#.data(using: .utf8)!, response: openAI
        )) { XCTAssertEqual($0 as? LLMError, .apiError("bad key")) }

        let qwen = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try LLMTransport.throwIfHTTPError(
            data: #"{"message":"rate limited"}"#.data(using: .utf8)!, response: qwen
        )) { XCTAssertEqual($0 as? LLMError, .apiError("rate limited")) }
    }

    func testStripFences() {
        XCTAssertEqual(LLMParsing.stripCodeFences("```json\n{\"a\":1}\n```"), "{\"a\":1}")
        XCTAssertEqual(LLMParsing.stripCodeFences("Sure! Here is the JSON: {\"a\":1} hope it helps"), "{\"a\":1}")
        XCTAssertEqual(LLMParsing.stripCodeFences("{\"a\":1}"), "{\"a\":1}")
    }

    func testLenientCorrectionResultDecode() throws {
        // A missing `corrected` falls back to the span; unknown keys are ignored.
        let json = """
        {
          "corrections": [
            {"original": "These"},
            {"original": "is", "corrected": "are", "pattern": "Subject-verb agreement"}
          ],
          "tip": "注意单复数哦"
        }
        """
        let result = try LLMParsing.decode(CorrectionResult.self, from: json)
        XCTAssertTrue(result.hasCorrections)
        XCTAssertEqual(result.corrections.count, 2)
        XCTAssertEqual(result.corrections[0].corrected, "These") // defaulted to the span
        XCTAssertEqual(result.corrections[1].corrected, "are")
        XCTAssertEqual(result.tip, "注意单复数哦")
    }

    func testMissingCorrectedPhraseFallsBackToOriginal() {
        let correction = Correction(SafeCorrection(original: "word"))
        XCTAssertEqual(correction.corrected, "word")
    }

    func testJSON5Tolerance() throws {
        let json5 = """
        {
          corrections: [],
          tip: "棒",
        }
        """
        let result = try LLMParsing.decode(CorrectionResult.self, from: json5)
        XCTAssertFalse(result.hasCorrections)
    }

    func testOpenAIEnvelope() throws {
        let data = #"{"choices":[{"message":{"content":"hello"}}]}"#.data(using: .utf8)!
        XCTAssertEqual(try LLMParsing.openAIMessageContent(from: data), "hello")
    }

    func testOpenAIErrorEnvelope() {
        let data = #"{"error":{"message":"bad key"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try LLMParsing.openAIMessageContent(from: data)) { error in
            XCTAssertEqual(error as? LLMError, .apiError("bad key"))
        }
    }

    func testOpenAIModelListEnvelope() throws {
        let data = #"{"object":"list","data":[{"id":"z-model"},{"id":"a-model","name":"A model"}]}"#.data(using: .utf8)!
        let models = try LLMParsing.openAIModels(from: data)
        XCTAssertEqual(models.map(\.id), ["z-model", "a-model"])
        XCTAssertEqual(models.last?.displayName, "A model")
    }

    func testGeminiEnvelope() throws {
        let data = #"{"candidates":[{"content":{"parts":[{"text":"a"},{"text":"b"}]}}]}"#.data(using: .utf8)!
        XCTAssertEqual(try LLMParsing.geminiContent(from: data), "ab")
    }

    func testGeminiModelListFiltersNonGenerationModels() throws {
        let data = #"{"models":[{"name":"models/gemini-2.5-flash","displayName":"Gemini Flash","supportedGenerationMethods":["generateContent"]},{"name":"models/text-embedding-005","supportedGenerationMethods":["embedContent"]}]}"#.data(using: .utf8)!
        let models = try LLMParsing.geminiModels(from: data)
        XCTAssertEqual(models.map(\.id), ["gemini-2.5-flash"])
        XCTAssertEqual(models.first?.displayName, "Gemini Flash")
    }

    func testGeminiModelListKeepsGenerationCapableMultimodalModels() throws {
        let data = #"{"models":[{"name":"models/gemini-2.5-flash-native-audio-preview","supportedGenerationMethods":["generateContent"]}]}"#.data(using: .utf8)!
        let models = try LLMParsing.geminiModels(from: data)
        XCTAssertEqual(models.map(\.id), ["gemini-2.5-flash-native-audio-preview"])
    }

    func testOpenAIStreamDelta() {
        let data = #"{"choices":[{"delta":{"content":" chunk "}}]}"#.data(using: .utf8)!
        XCTAssertEqual(LLMParsing.openAIStreamDelta(from: data), " chunk ")
        let role = #"{"choices":[{"delta":{"role":"assistant"}}]}"#.data(using: .utf8)!
        XCTAssertNil(LLMParsing.openAIStreamDelta(from: role))
    }

    func testGeminiStreamDelta() {
        let data = #"{"candidates":[{"content":{"parts":[{"text":"你好"}]}}]}"#.data(using: .utf8)!
        XCTAssertEqual(LLMParsing.geminiStreamDelta(from: data), "你好")
    }
}

final class TextSegmentTests: XCTestCase {
    func testSegments() {
        let corrections = [
            Correction(original: "These", corrected: "This"),
            Correction(original: "explian", corrected: "explanation"),
        ]
        let segments = TextSegment.segments(for: "These is your explian.", corrections: corrections)
        XCTAssertEqual(segments.count, 4)
        guard case .correction(let c0) = segments[0] else { return XCTFail() }
        XCTAssertEqual(c0.original, "These")
        guard case .plain(let p1) = segments[1] else { return XCTFail() }
        XCTAssertEqual(p1, " is your ")
        guard case .correction(let c2) = segments[2] else { return XCTFail() }
        XCTAssertEqual(c2.corrected, "explanation")
        guard case .plain(let p3) = segments[3] else { return XCTFail() }
        XCTAssertEqual(p3, ".")
    }

    func testMissingCorrectionIsSkipped() {
        let corrections = [Correction(original: "nothere", corrected: "x")]
        let segments = TextSegment.segments(for: "hello world", corrections: corrections)
        XCTAssertEqual(segments, [.plain("hello world")])
    }
}

final class InlineDiffTests: XCTestCase {
    func testIdenticalTextReturnsUnchanged() {
        let diff = InlineDiff.diff(original: "hello world", corrected: "hello world")
        XCTAssertEqual(diff, [.unchanged("hello world")])
    }

    func testSimpleWordReplacement() {
        let diff = InlineDiff.diff(original: "These", corrected: "This")
        XCTAssertEqual(diff, [.deleted("These"), .inserted("This")])
    }

    func testInsertionInMiddle() {
        let diff = InlineDiff.diff(original: "context object", corrected: "the context object")
        XCTAssertEqual(diff, [.inserted("the "), .unchanged("context object")])
    }

    func testSentenceLevelPreservesUnchangedSpans() {
        let orig = "`RunContextWrapper` is context object we passed to `Runner.run()`"
        let corr = "`RunContextWrapper` is the context object we pass to `Runner.run()`"
        let diff = InlineDiff.diff(original: orig, corrected: corr)

        // Verifies `RunContextWrapper` and `Runner.run()` are preserved as unchanged
        guard case .unchanged(let first) = diff.first else { return XCTFail("Expected unchanged start, got \(String(describing: diff.first))") }
        XCTAssertTrue(first.contains("RunContextWrapper"))

        guard case .unchanged(let last) = diff.last else { return XCTFail("Expected unchanged end, got \(String(describing: diff.last))") }
        XCTAssertTrue(last.contains("Runner.run()"))
    }
}

final class SplicingTests: XCTestCase {
    private func result(_ corrections: [Correction]) -> CorrectionResult {
        CorrectionResult(corrections: corrections, tip: "")
    }

    func testSplicePreservesUntouchedBytes() {
        // The splice must keep the user's document byte-identical outside the fix.
        let result = result([Correction(original: "Grammer", corrected: "Grammar")])
        XCTAssertEqual(
            result.splicingCorrections(into: "> adjust Chinese test text in Grammer check"),
            "> adjust Chinese test text in Grammar check"
        )
    }

    func testSpliceAppliesCorrectionsInOrder() {
        let result = result(
            [
                Correction(original: "These", corrected: "This"),
                Correction(original: "explian", corrected: "explanation"),
            ]
        )
        XCTAssertEqual(
            result.splicingCorrections(into: "These is your explian."),
            "This is your explanation."
        )
    }

    func testSpliceReturnsNilWhenNothingMatched() {
        let result = result(
            [Correction(original: "nothere", corrected: "x")]
        )
        XCTAssertNil(result.splicingCorrections(into: "hello world"))
    }

    func testSpliceHandlesInsertionAnchors() {
        let result = result(
            [Correction(original: "a explanation", corrected: "an explanation")]
        )
        XCTAssertEqual(
            result.splicingCorrections(into: "He gave a explanation yesterday."),
            "He gave an explanation yesterday."
        )
    }
}

final class ProviderConfigTests: XCTestCase {
    func testTaskModelsAreStoredIndependently() {
        let domain = "YagrakerCoreTests.TaskModels.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.model(for: .qwen, task: .translation), "qwen-mt-flash")
        XCTAssertEqual(store.model(for: .qwen, task: .grammar), "")
        XCTAssertEqual(store.model(for: .qwen, task: .deepRead), "")

        store.setModel("qwen-mt-plus", for: .qwen, task: .translation)
        store.setModel("qwen3.7-plus", for: .qwen, task: .grammar)
        store.setModel("qwen3.7-flash", for: .qwen, task: .deepRead)

        XCTAssertEqual(store.model(for: .qwen, task: .translation), "qwen-mt-plus")
        XCTAssertEqual(store.model(for: .qwen, task: .grammar), "qwen3.7-plus")
        XCTAssertEqual(store.model(for: .qwen, task: .deepRead), "qwen3.7-flash")
    }

    func testQwenBaseURLValidation() {
        XCTAssertTrue(QwenService.isValidBaseURL(QwenService.defaultBaseURL))
        XCTAssertTrue(QwenService.isValidBaseURL("https://workspace.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"))
        XCTAssertFalse(QwenService.isValidBaseURL("http://dashscope.aliyuncs.com/compatible-mode/v1"))
        XCTAssertFalse(QwenService.isValidBaseURL("https://dashscope.aliyuncs.com/compatible-mode/v1?unsafe=true"))
    }

    func testBlankQwenBaseURLUsesDefaultEndpoint() {
        let domain = "YagrakerCoreTests.QwenBaseURL.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = SettingsStore(defaults: defaults)

        defaults.set("   ", forKey: "provider.qwen.baseURL")
        XCTAssertEqual(store.qwenBaseURL, QwenService.defaultBaseURL)
    }

    func testMiMoClusterEndpoints() {
        XCTAssertEqual(MiMoCluster.cn.baseURL, "https://token-plan-cn.xiaomimimo.com/v1")
        XCTAssertEqual(MiMoCluster.sg.baseURL, "https://token-plan-sgp.xiaomimimo.com/v1")
        XCTAssertEqual(MiMoCluster.eu.baseURL, "https://token-plan-ams.xiaomimimo.com/v1")
    }

    func testMiMoModelCatalogRecognizesTextGenerationModels() {
        XCTAssertTrue(MiMoService.isTextGenerationModel("mimo-v2.5"))
        XCTAssertTrue(MiMoService.isTextGenerationModel("mimo-v2.5-pro"))
        XCTAssertFalse(MiMoService.isTextGenerationModel("mimo-v2.5-asr"))
        XCTAssertFalse(MiMoService.isTextGenerationModel("mimo-v2.5-tts-voiceclone"))
        XCTAssertFalse(MiMoService.isTextGenerationModel("  "))
    }

    func testCustomEndpointValidation() {
        let service = CustomService()
        service.baseURLProvider = { "" }
        XCTAssertThrowsError(try service.endpoint()) { XCTAssertEqual($0 as? LLMError, .baseURLEmpty) }

        service.baseURLProvider = { "not a url at all %%" }
        XCTAssertThrowsError(try service.endpoint())

        service.baseURLProvider = { "https://example.com/v1/" }
        XCTAssertEqual(try service.endpoint().absoluteString, "https://example.com/v1/chat/completions")

        service.baseURLProvider = { "http://example.com/v1" }
        XCTAssertThrowsError(try service.endpoint())

        service.baseURLProvider = { "http://127.evil.example/v1" }
        XCTAssertThrowsError(try service.endpoint())

        service.baseURLProvider = { "https://example.com/v1?unsafe=true" }
        XCTAssertThrowsError(try service.endpoint())

        service.baseURLProvider = { "http://127.0.0.1:8080/v1" }
        XCTAssertEqual(try service.endpoint().absoluteString, "http://127.0.0.1:8080/v1/chat/completions")

        service.baseURLProvider = { "http://192.168.1.20:8080/v1" }
        XCTAssertEqual(try service.endpoint().absoluteString, "http://192.168.1.20:8080/v1/chat/completions")
    }

    func testMiMoDefaultModelIsV25() {
        XCTAssertEqual(LLMProviderKind.mimo.defaultModel(for: .translation), "mimo-v2.5")
        XCTAssertEqual(LLMProviderKind.mimo.defaultModel(for: .deepRead), "mimo-v2.5")
        XCTAssertEqual(LLMProviderKind.qwen.defaultModel(for: .translation), "qwen-mt-flash")
        XCTAssertEqual(LLMProviderKind.qwen.defaultModel(for: .grammar), "")
        XCTAssertEqual(LLMProviderKind.qwen.defaultModel(for: .deepRead), "")
    }

    func testQwenTranslationModelCatalogMatchesSupportedModels() {
        XCTAssertEqual(
            QwenService.supportedTranslationModels.map(\.rawValue),
            ["qwen-mt-plus", "qwen-mt-flash", "qwen-mt-lite", "qwen-mt-turbo"]
        )
        XCTAssertTrue(QwenService.supportsIncrementalStreaming("qwen-mt-flash"))
        XCTAssertTrue(QwenService.supportsIncrementalStreaming("qwen-mt-lite"))
        XCTAssertFalse(QwenService.supportsIncrementalStreaming("qwen-mt-plus"))
        XCTAssertFalse(QwenService.supportsIncrementalStreaming("qwen-mt-turbo"))
    }

    func testTranslationDirectionFollowsInputLanguage() {
        let zhHans = ReaderLanguage.simplifiedChinese
        XCTAssertEqual(TranslationTargetLanguage.inferred(from: "hello world", for: zhHans), .simplifiedChinese)
        XCTAssertEqual(TranslationTargetLanguage.inferred(from: "你好，世界", for: zhHans), .english)
        // A Chinese sentence quoting English terms is still Chinese.
        XCTAssertEqual(TranslationTargetLanguage.inferred(from: "使用 Kubernetes 部署服务", for: zhHans), .english)
        // An English sentence with a Chinese name is still English.
        XCTAssertEqual(TranslationTargetLanguage.inferred(from: "I love 北京 in the spring", for: zhHans), .simplifiedChinese)
        // Japanese kanji must not count as Chinese; Korean has no Han at all.
        XCTAssertEqual(TranslationTargetLanguage.inferred(from: "東京に行きます", for: zhHans), .simplifiedChinese)
        XCTAssertEqual(TranslationTargetLanguage.inferred(from: "서울에 갑니다", for: zhHans), .simplifiedChinese)
        // Code-only input has no direction; the prompt returns it unchanged.
        XCTAssertEqual(TranslationTargetLanguage.inferred(from: "let x = foo(bar)", for: zhHans), .simplifiedChinese)
        // The reader's UI language picks the Chinese variant of the zh⇄en pair.
        XCTAssertEqual(TranslationTargetLanguage.inferred(from: "hello world", for: .traditionalChinese), .traditionalChinese)
        XCTAssertEqual(TranslationTargetLanguage.inferred(from: "hello world", for: .english), .simplifiedChinese)
        XCTAssertEqual(TranslationTargetLanguage.inferred(from: "你好", for: .traditionalChinese), .english)
        XCTAssertEqual(TranslationTargetLanguage.traditionalChinese.rawValue, "Traditional Chinese")
    }
}

final class OpenAIRequestShapeTests: ServiceTestCase {

    func testModelListRequiresAPIKey() async {
        let service = DeepSeekService(session: session)
        do {
            _ = try await service.listModels(apiKey: "  ")
            XCTFail("an empty API key must be rejected")
        } catch {
            XCTAssertEqual(error as? LLMError, .noAPIKey)
        }
    }

    func testModelListUsesProviderModelsEndpoint() async throws {
        let captured = expectation(description: "captured request")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
            captured.fulfill()
            let payload = #"{"object":"list","data":[{"id":"deepseek-v4-flash"}]}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                payload.data(using: .utf8)!
            )
        }
        let service = DeepSeekService(session: session)
        let models = try await service.listModels(apiKey: "k")
        XCTAssertEqual(models.map(\.id), ["deepseek-v4-flash"])
        await fulfillment(of: [captured], timeout: 5)
    }

    func testMiMoModelListUsesClusterModelsEndpoint() async throws {
        let captured = expectation(description: "captured request")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://token-plan-sgp.xiaomimimo.com/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
            captured.fulfill()
            let payload = #"{"object":"list","data":[{"id":"mimo-v2.5"},{"id":"mimo-v2.5-asr"},{"id":"mimo-v2.5-pro"},{"id":"mimo-v2.5-tts"}]}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                payload.data(using: .utf8)!
            )
        }
        let service = MiMoService(session: session)
        service.setCluster(.sg)
        let models = try await service.listModels(apiKey: "k")
        XCTAssertEqual(models.map(\.id), ["mimo-v2.5", "mimo-v2.5-asr", "mimo-v2.5-pro", "mimo-v2.5-tts"])
        await fulfillment(of: [captured], timeout: 5)
    }

    func testDeepSeekGrammarRequestShape() async throws {
        let captured = expectation(description: "captured request")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
            let body = self.lastRequestBody(request)
            XCTAssertEqual(body["model"] as? String, "m")
            XCTAssertNil(body["temperature"])
            XCTAssertNil(body["max_tokens"])
            XCTAssertNotNil(body["response_format"])
            XCTAssertEqual(body["stream"] as? Bool, true)
            let messages = body["messages"] as? [[String: String]]
            XCTAssertEqual(messages?.first?["role"], "system")
            XCTAssertTrue(messages?.first?["content"]?.contains("Review English writing") ?? false)
            XCTAssertFalse(messages?.first?["content"]?.contains(#""translation""#) ?? true)
            XCTAssertTrue(messages?.last?["content"]?.contains("Review the text below") ?? false)
            captured.fulfill()
            let text = #"{"corrections":[],"tip":"s"}"#
            let event = #"{"choices":[{"delta":{"content":\#(self.jsonString(text))}}]}"#
            let payload = "data: \(event)\n\ndata: [DONE]\n\n"
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload.data(using: .utf8)!)
        }
        let service = DeepSeekService(session: session)
        let result = try await service.checkGrammar(request: GrammarCheckRequest(text: "hello", reader: .simplifiedChinese), apiKey: "k", model: "m")
        XCTAssertEqual(result.tip, "s")
        await fulfillment(of: [captured], timeout: 5)
    }

    func testMiMoSendsMaxCompletionTokens() async throws {
        let captured = expectation(description: "captured request")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://token-plan-cn.xiaomimimo.com/v1/chat/completions")
            let body = self.lastRequestBody(request)
            XCTAssertNotNil(body["max_completion_tokens"])
            XCTAssertNil(body["max_tokens"])
            captured.fulfill()
            let payload = "data: {\"choices\":[{\"delta\":{\"content\":\"甲\"}}]}\n\ndata: [DONE]\n\n"
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!,
                payload.data(using: .utf8)!
            )
        }
        let service = MiMoService(session: session)
        var result = ""
        for try await delta in service.streamText(
            task: .translation,
            text: "a",
            systemPrompt: "sys",
            targetLanguage: .simplifiedChinese,
            apiKey: "k",
            model: "m"
        ) {
            result += delta
        }
        XCTAssertEqual(result, "甲")
        await fulfillment(of: [captured], timeout: 5)
    }

    func testStreamingParsesDeltas() async throws {
        MockURLProtocol.handler = { request in
            let body = self.lastRequestBody(request)
            let messages = body["messages"] as? [[String: String]]
            XCTAssertTrue(messages?.first?["content"]?.contains("Chinese-speaking reader") ?? false)
            XCTAssertNil(body["translation_options"])
            let sse = """
            data: {"choices":[{"delta":{"content":"你"}}]}

            data: {"choices":[{"delta":{"content":"好"}}]}

            data: [DONE]

            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
            return (response, sse.data(using: .utf8)!)
        }
        let service = DeepSeekService(session: session)
        var collected = ""
        for try await delta in service.streamText(
            task: .deepRead,
            text: "Although it looks simple, the clause is difficult.",
            systemPrompt: Prompts.deepReadSystem(target: .simplifiedChinese, reader: .simplifiedChinese),
            targetLanguage: .simplifiedChinese,
            apiKey: "k",
            model: "m"
        ) {
            collected += delta
        }
        XCTAssertEqual(collected, "你好")
    }
}

final class QwenRequestShapeTests: ServiceTestCase {
    func testQwenModelListUsesConfiguredBaseURL() async throws {
        let captured = expectation(description: "captured request")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://qwen.test/api/v1/models?providers=qwen&capabilities=TG&page_no=1&page_size=100"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
            captured.fulfill()
            let payload = #"{"success":true,"code":null,"message":null,"output":{"total":2,"page_no":1,"page_size":100,"models":[{"model":"qwen-mt-flash","name":"Qwen-MT Flash"},{"model":"qwen-plus"}]}}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                payload.data(using: .utf8)!
            )
        }
        let service = QwenService(session: session)
        service.baseURLProvider = { "https://qwen.test/compatible-mode/v1" }
        let models = try await service.listModels(apiKey: "k")
        XCTAssertEqual(models.map(\.id), ["qwen-mt-flash", "qwen-mt-lite", "qwen-mt-plus", "qwen-mt-turbo", "qwen-plus"])
        await fulfillment(of: [captured], timeout: 5)
    }

    func testMachineTranslationStreamingUsesSSE() async throws {
        let captured = expectation(description: "captured request")
        MockURLProtocol.handler = { request in
            let body = self.lastRequestBody(request)
            XCTAssertEqual(body["model"] as? String, "qwen-mt-flash")
            XCTAssertEqual(body["stream"] as? Bool, true)
            let options = body["translation_options"] as? [String: Any]
            XCTAssertEqual(options?["target_lang"] as? String, "Chinese")
            captured.fulfill()
            let sse = """
            data: {"choices":[{"delta":{"content":"你"}}]}

            data: {"choices":[{"delta":{"content":"好"}}]}

            data: [DONE]

            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!, sse.data(using: .utf8)!)
        }

        let service = QwenService(session: session)
        service.baseURLProvider = { "https://qwen.test/compatible-mode/v1" }
        var collected = ""
        var chunks: [String] = []
        for try await delta in service.streamText(
            task: .translation,
            text: "hello",
            systemPrompt: "ignored",
            targetLanguage: .simplifiedChinese,
            apiKey: "k",
            model: "qwen-mt-flash"
        ) {
            collected += delta
            chunks.append(delta)
        }

        XCTAssertEqual(collected, "你好")
        XCTAssertEqual(chunks, ["你", "好"])
        await fulfillment(of: [captured], timeout: 5)
    }

    func testMachineTranslationChineseInputTargetsEnglish() async throws {
        let captured = expectation(description: "captured request")
        MockURLProtocol.handler = { request in
            let body = self.lastRequestBody(request)
            let options = body["translation_options"] as? [String: Any]
            XCTAssertEqual(options?["target_lang"] as? String, "English")
            captured.fulfill()
            let payload = #"{"choices":[{"message":{"content":"Hello"}}]}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                payload.data(using: .utf8)!
            )
        }

        let service = QwenService(session: session)
        service.baseURLProvider = { "https://qwen.test/compatible-mode/v1" }
        var result = ""
        for try await delta in service.streamText(
            task: .translation,
            text: "你好",
            systemPrompt: "ignored",
            targetLanguage: .english,
            apiKey: "k",
            model: "qwen-mt-plus"
        ) {
            result += delta
        }

        XCTAssertEqual(result, "Hello")
        await fulfillment(of: [captured], timeout: 5)
    }

    func testMachineTranslationNonIncrementalModelsUseOneShotRequest() async throws {
        let captured = expectation(description: "captured request")
        MockURLProtocol.handler = { request in
            let body = self.lastRequestBody(request)
            XCTAssertEqual(body["model"] as? String, "qwen-mt-plus")
            XCTAssertEqual(body["stream"] as? Bool, false)
            captured.fulfill()
            let payload = #"{"choices":[{"message":{"content":"你好"}}]}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                payload.data(using: .utf8)!
            )
        }

        let service = QwenService(session: session)
        service.baseURLProvider = { "https://qwen.test/compatible-mode/v1" }
        var collected = ""
        for try await delta in service.streamText(
            task: .translation,
            text: "hello",
            systemPrompt: "ignored",
            targetLanguage: .simplifiedChinese,
            apiKey: "k",
            model: "qwen-mt-plus"
        ) {
            collected += delta
        }

        XCTAssertEqual(collected, "你好")
        await fulfillment(of: [captured], timeout: 5)
    }

    func testMachineTranslationModelCannotRunGrammarCheck() async {
        let service = QwenService(session: session)
        do {
            _ = try await service.checkGrammar(
                request: GrammarCheckRequest(text: "hello", reader: .simplifiedChinese),
                apiKey: "k",
                model: "qwen-mt-flash"
            )
            XCTFail("qwen-mt models must not be used for grammar checking")
        } catch {
            XCTAssertEqual(
                error as? LLMError,
                .modelUnsupported(task: .grammar, model: "qwen-mt-flash")
            )
        }
    }

    func testMachineTranslationModelCannotRunDeepRead() async {
        let service = QwenService(session: session)
        do {
            for try await _ in service.streamText(
                task: .deepRead,
                text: "Although it looks simple, the clause is difficult.",
                systemPrompt: Prompts.deepReadSystem(target: .simplifiedChinese, reader: .simplifiedChinese),
                targetLanguage: .simplifiedChinese,
                apiKey: "k",
                model: "qwen-mt-flash"
            ) {}
            XCTFail("qwen-mt models must not be used for deep reading")
        } catch {
            XCTAssertEqual(
                error as? LLMError,
                .modelUnsupported(task: .deepRead, model: "qwen-mt-flash")
            )
        }
    }
}

final class GeminiRequestShapeTests: ServiceTestCase {
    func testGeminiModelListUsesOfficialEndpointAndPagination() async throws {
        let captured = expectation(description: "captured requests")
        var requestCount = 0
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("/v1beta/models") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("key=k") ?? false)
            requestCount += 1
            let body: String
            if requestCount == 1 {
                body = #"{"models":[{"name":"models/gemini-2.5-flash","supportedGenerationMethods":["generateContent"]}],"nextPageToken":"next"}"#
            } else {
                XCTAssertTrue(request.url?.absoluteString.contains("pageToken=next") ?? false)
                captured.fulfill()
                body = #"{"models":[{"name":"models/gemini-2.5-pro","supportedGenerationMethods":["generateContent"]}]}"#
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body.data(using: .utf8)!
            )
        }
        let service = GeminiService(session: session)
        let models = try await service.listModels(apiKey: "k")
        XCTAssertEqual(models.map(\.id), ["gemini-2.5-flash", "gemini-2.5-pro"])
        await fulfillment(of: [captured], timeout: 5)
    }

    func testGeminiGrammarUsesResponseSchema() async throws {
        let captured = expectation(description: "captured request")
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains(":streamGenerateContent") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("alt=sse") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("gemini-3-flash-preview") ?? false)
            let body = self.lastRequestBody(request)
            let config = body["generationConfig"] as? [String: Any]
            XCTAssertEqual(config?["responseMimeType"] as? String, "application/json")
            let schema = config?["responseSchema"] as? [String: Any]
            let properties = schema?["properties"] as? [String: Any]
            let required = schema?["required"] as? [String]
            XCTAssertNil(properties?["translation"])
            XCTAssertFalse(required?.contains("translation") ?? true)
            XCTAssertNotNil(body["systemInstruction"])
            captured.fulfill()
            let text = "{\"corrections\":[],\"tip\":\"s\"}"
            let event = "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\(self.jsonString(text))}]}}]}"
            let payload = "data: \(event)\n\n"
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload.data(using: .utf8)!)
        }
        let service = GeminiService(session: session)
        let result = try await service.checkGrammar(request: GrammarCheckRequest(text: "hello", reader: .simplifiedChinese), apiKey: "k", model: "gemini-3-flash-preview")
        XCTAssertEqual(result.tip, "s")
        await fulfillment(of: [captured], timeout: 5)
    }

    func testGeminiStreamingUsesAltSSE() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains(":streamGenerateContent") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("alt=sse") ?? false)
            let sse = """
            data: {"candidates":[{"content":{"parts":[{"text":"你"}]}}]}

            data: {"candidates":[{"content":{"parts":[{"text":"好"}]}}]}

            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, sse.data(using: .utf8)!)
        }
        let service = GeminiService(session: session)
        var collected = ""
        for try await delta in service.streamText(
            task: .translation,
            text: "hi",
            systemPrompt: "sys",
            targetLanguage: .simplifiedChinese,
            apiKey: "k",
            model: "m"
        ) {
            collected += delta
        }
        XCTAssertEqual(collected, "你好")
    }

}
