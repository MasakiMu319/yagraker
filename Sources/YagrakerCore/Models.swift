import Foundation

// MARK: - Providers

public enum LLMTask: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case translation
    case deepRead
    case grammar

    public var id: String { rawValue }
}

public enum LLMProviderKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case gemini, qwen, mimo, deepseek, custom

    public var id: String { rawValue }

    public func modelDefaultsKey(for task: LLMTask) -> String {
        "provider.\(rawValue).\(task.rawValue)Model"
    }

    public func defaultModel(for task: LLMTask) -> String {
        switch (self, task) {
        case (.gemini, _): return "gemini-3-flash-preview"
        case (.qwen, .translation): return "qwen-mt-flash"
        case (.qwen, .deepRead), (.qwen, .grammar): return ""
        case (.deepseek, _): return "deepseek-v4-flash"
        case (.mimo, _): return "mimo-v2.5"
        case (.custom, _): return ""
        }
    }

    public var defaultDisplayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .qwen: return "Qwen"
        case .mimo: return "MiMo"
        case .deepseek: return "DeepSeek"
        case .custom: return "Custom"
        }
    }
}

/// A model advertised by a provider's official model-list endpoint.
public struct LLMModel: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let displayName: String?
    public let description: String?

    public init(id: String, displayName: String? = nil, description: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.description = description
    }

    public var label: String {
        guard let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              displayName != id else { return id }
        return "\(displayName) (\(id))"
    }
}

public enum QwenTranslationModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case plus = "qwen-mt-plus"
    case flash = "qwen-mt-flash"
    case lite = "qwen-mt-lite"
    case turbo = "qwen-mt-turbo"

    public var id: String { rawValue }

    public var supportsIncrementalStreaming: Bool {
        self == .flash || self == .lite
    }

    public var isDeprecated: Bool {
        self == .turbo
    }
}

public enum MiMoCluster: String, CaseIterable, Identifiable, Codable, Sendable {
    case cn, sg, eu

    public var id: String { rawValue }

    public var baseURL: String {
        switch self {
        case .cn: return "https://token-plan-cn.xiaomimimo.com/v1"
        case .sg: return "https://token-plan-sgp.xiaomimimo.com/v1"
        case .eu: return "https://token-plan-ams.xiaomimimo.com/v1"
        }
    }
}

public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    public var id: String { rawValue }

    /// nil = follow system.
    public var localeCode: String? {
        self == .system ? nil : rawValue
    }

    /// Concrete language for this setting; `.system` follows the OS preference
    /// list and falls back to English when nothing matches.
    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> ReaderLanguage {
        switch self {
        case .english: return .english
        case .simplifiedChinese: return .simplifiedChinese
        case .traditionalChinese: return .traditionalChinese
        case .system:
            for preferred in preferredLanguages {
                let lang = preferred.lowercased()
                if lang.hasPrefix("zh") {
                    let traditional = lang.contains("hant") || lang.contains("-tw") || lang.contains("-hk") || lang.contains("-mo")
                    return traditional ? .traditionalChinese : .simplifiedChinese
                }
                if lang.hasPrefix("en") { return .english }
            }
            return .english
        }
    }
}

/// The language the user reads: UI strings, explanations, analysis, and the
/// Chinese side of translation. Raw values match the `.lproj` folder names.
public enum ReaderLanguage: String, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
}

// MARK: - Errors

public enum LLMError: LocalizedError, Equatable, Sendable {
    case noProvider
    case noAPIKey
    case modelEmpty
    case modelUnsupported(task: LLMTask, model: String)
    case baseURLEmpty
    case invalidBaseURL(String)
    case apiError(String)
    case networkError(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .noProvider: return "error.noProvider"
        case .noAPIKey: return "error.noAPIKey"
        case .modelEmpty: return "error.modelEmpty"
        case .modelUnsupported(let task, let model): return "error.modelUnsupported|\(task.rawValue)|\(model)"
        case .baseURLEmpty: return "error.baseURLEmpty"
        case .invalidBaseURL(let url): return "error.invalidBaseURL|\(url)"
        case .apiError(let msg): return "error.apiError|\(msg)"
        case .networkError(let msg): return "error.networkError|\(msg)"
        case .invalidResponse: return "error.invalidResponse"
        }
    }

    /// Localized via L10n at the UI layer.
    public var message: String {
        switch self {
        case .noProvider: return "No configured AI provider. Add an API key and model in Settings."
        case .noAPIKey: return "No API key configured. Please set your API key in Settings."
        case .modelEmpty: return "Model is empty. Set it in Settings."
        case .modelUnsupported(let task, let model):
            let taskName = switch task {
            case .translation: "translation"
            case .deepRead: "deep reading"
            case .grammar: "grammar checking"
            }
            return "Model \(model) does not support \(taskName). Choose a model intended for that task."
        case .baseURLEmpty: return "Base URL is empty. Set it in Settings."
        case .invalidBaseURL(let url): return "Invalid Base URL: \(url)"
        case .apiError(let msg): return "API error: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .invalidResponse: return "Failed to parse AI response. Please try again."
        }
    }
}

// MARK: - Grammar

public struct GrammarCheckRequest: Sendable {
    public var text: String
    public var reader: ReaderLanguage

    public init(text: String, reader: ReaderLanguage) {
        self.text = text
        self.reader = reader
    }
}

/// Lenient decoding wrapper: tolerates incomplete correction objects
/// (a missing `corrected` falls back to the original span instead of failing the whole payload).
public struct SafeCorrection: Codable, Sendable {
    public var original: String?
    public var corrected: String?

    public init(original: String? = nil, corrected: String? = nil) {
        self.original = original
        self.corrected = corrected
    }
}

public struct Correction: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var original: String
    public var corrected: String

    public init(id: UUID = UUID(), original: String, corrected: String) {
        self.id = id
        self.original = original
        self.corrected = corrected
    }

    public init(_ safe: SafeCorrection) {
        let original = safe.original ?? ""
        let corrected = safe.corrected.flatMap { $0.isEmpty ? nil : $0 } ?? original
        self.init(original: original, corrected: corrected)
    }

    private enum CodingKeys: String, CodingKey {
        case original, corrected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let safe = SafeCorrection(
            original: try container.decodeIfPresent(String.self, forKey: .original),
            corrected: try container.decodeIfPresent(String.self, forKey: .corrected)
        )
        self.init(safe)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(original, forKey: .original)
        try container.encode(corrected, forKey: .corrected)
    }
}

public struct CorrectionResult: Codable, Sendable {
    public var corrections: [Correction]
    public var tip: String

    public init(corrections: [Correction], tip: String) {
        self.corrections = corrections
        self.tip = tip
    }

    public var hasCorrections: Bool { !corrections.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case corrections, tip
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let safeCorrections = try container.decodeIfPresent([SafeCorrection].self, forKey: .corrections) ?? []
        let tip = try container.decodeIfPresent(String.self, forKey: .tip) ?? ""
        self.init(
            corrections: safeCorrections.map(Correction.init).filter { !$0.original.isEmpty },
            tip: tip
        )
    }
}

extension CorrectionResult {
    /// Apply corrections onto `original` left-to-right (literal,
    /// non-overlapping — same matching semantics as `TextSegment.segments`),
    /// keeping every byte outside corrected spans identical to the captured
    /// source. Returns nil when no correction span matched, which means the
    /// model's spans are unusable for this text.
    public func splicingCorrections(into original: String) -> String? {
        var output = ""
        var cursor = original.startIndex
        var matchedAny = false
        for correction in corrections where !correction.original.isEmpty {
            guard let range = original.range(
                of: correction.original,
                options: [.literal],
                range: cursor..<original.endIndex
            ) else { continue }
            output += original[cursor..<range.lowerBound]
            output += correction.corrected
            cursor = range.upperBound
            matchedAny = true
        }
        guard matchedAny else { return nil }
        output += original[cursor...]
        return output
    }
}

public struct GrammarHistoryEntry: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let originalText: String
    public let result: CorrectionResult

    public init(id: UUID = UUID(), date: Date = Date(), originalText: String, result: CorrectionResult) {
        self.id = id
        self.date = date
        self.originalText = originalText
        self.result = result
    }

    public var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Translation

/// Raw values are the `target_lang` names accepted by Qwen-MT.
public enum TranslationTargetLanguage: String, Sendable {
    case english = "English"
    case simplifiedChinese = "Chinese"
    case traditionalChinese = "Traditional Chinese"

    /// The Chinese⇄English pair: predominantly Chinese text goes to English,
    /// everything else to the reader's Chinese variant.
    public static func inferred(from text: String, for reader: ReaderLanguage) -> Self {
        let chinese: Self = reader == .traditionalChinese ? .traditionalChinese : .simplifiedChinese
        return isPredominantlyChinese(text) ? .english : chinese
    }

    /// Han characters are weighed against Latin words, so a Chinese sentence
    /// that quotes a few English terms still counts as Chinese. Any hiragana
    /// or katakana marks the text as Japanese, whose kanji would otherwise
    /// count as Han.
    static func isPredominantlyChinese(_ text: String) -> Bool {
        var han = 0
        var latinWords = 0
        var inLatinWord = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3041...0x3096, 0x30A1...0x30FA:
                return false
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                han += 1
                inLatinWord = false
            case 0x0041...0x005A, 0x0061...0x007A:
                if !inLatinWord {
                    latinWords += 1
                    inLatinWord = true
                }
            default:
                inLatinWord = false
            }
        }
        return han > latinWords
    }
}

// MARK: - UI models

/// A slice of the original text, split around corrections.
public enum TextSegment: Identifiable, Hashable, Sendable {
    case plain(String)
    case correction(Correction)

    public var id: String {
        switch self {
        case .plain(let text): return "plain:\(text.hashValue)"
        case .correction(let correction): return "correction:\(correction.id.uuidString)"
        }
    }

    /// Split `originalText` into plain/correction segments by locating each
    /// correction's `original` phrase left-to-right (literal, non-overlapping).
    public static func segments(for originalText: String, corrections: [Correction]) -> [TextSegment] {
        var segments: [TextSegment] = []
        var searchStart = originalText.startIndex
        for correction in corrections where !correction.original.isEmpty {
            guard let range = originalText.range(
                of: correction.original,
                options: [.literal],
                range: searchStart..<originalText.endIndex
            ) else { continue }
            if searchStart < range.lowerBound {
                segments.append(.plain(String(originalText[searchStart..<range.lowerBound])))
            }
            segments.append(.correction(correction))
            searchStart = range.upperBound
        }
        if searchStart < originalText.endIndex {
            segments.append(.plain(String(originalText[searchStart...])))
        }
        return segments
    }
}
