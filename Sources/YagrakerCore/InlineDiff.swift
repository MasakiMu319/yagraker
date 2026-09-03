import Foundation

public enum DiffChunk: Hashable, Sendable {
    case unchanged(String)
    case deleted(String)
    case inserted(String)
}

public enum InlineDiff {
    /// Compute a token-level diff between `original` and `corrected`.
    /// Identical tokens are emitted as `.unchanged`.
    /// Tokens present in `original` but not in `corrected` are emitted as `.deleted`.
    /// Tokens present in `corrected` but not in `original` are emitted as `.inserted`.
    public static func diff(original: String, corrected: String) -> [DiffChunk] {
        if original == corrected {
            return original.isEmpty ? [] : [.unchanged(original)]
        }
        if original.isEmpty {
            return [.inserted(corrected)]
        }
        if corrected.isEmpty {
            return [.deleted(original)]
        }

        let tokensA = tokenize(original)
        let tokensB = tokenize(corrected)

        let n = tokensA.count
        let m = tokensB.count

        // Guard against massive payloads causing high computational complexity
        if n > 600 || m > 600 {
            return [.deleted(original), .inserted(corrected)]
        }

        // DP table for Longest Common Subsequence (LCS)
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if tokensA[i - 1] == tokensB[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to assemble diff chunks
        var rawChunks: [DiffChunk] = []
        var i = n
        var j = m

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && tokensA[i - 1] == tokensB[j - 1] {
                rawChunks.append(.unchanged(tokensA[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                rawChunks.append(.inserted(tokensB[j - 1]))
                j -= 1
            } else if i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j]) {
                rawChunks.append(.deleted(tokensA[i - 1]))
                i -= 1
            }
        }

        rawChunks.reverse()
        return merge(rawChunks)
    }

    /// Tokenize text into words, whitespace, and punctuation, preserving every character.
    public static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentKind: TokenKind?

        enum TokenKind {
            case word
            case whitespace
            case punctuation
        }

        for char in text {
            let kind: TokenKind
            if char.isWhitespace {
                kind = .whitespace
            } else if char.isLetter || char.isNumber || char == "_" {
                kind = .word
            } else {
                kind = .punctuation
            }

            if let ck = currentKind, ck == kind {
                current.append(char)
            } else {
                if !current.isEmpty {
                    tokens.append(current)
                }
                current = String(char)
                currentKind = kind
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func merge(_ chunks: [DiffChunk]) -> [DiffChunk] {
        var merged: [DiffChunk] = []
        for chunk in chunks {
            guard let last = merged.last else {
                merged.append(chunk)
                continue
            }
            switch (last, chunk) {
            case (.unchanged(let a), .unchanged(let b)):
                merged[merged.count - 1] = .unchanged(a + b)
            case (.deleted(let a), .deleted(let b)):
                merged[merged.count - 1] = .deleted(a + b)
            case (.inserted(let a), .inserted(let b)):
                merged[merged.count - 1] = .inserted(a + b)
            default:
                merged.append(chunk)
            }
        }
        return merged
    }
}
