import Foundation

/// Aligns what the speaker just said with a position in the script.
///
/// Speech recognition output is noisy and always a little behind, so instead of
/// requiring an exact match we score a short window of recent words against every
/// candidate position ahead of the cursor and take the best one.
struct ScriptMatcher {
    private let tokens: [String]
    private let lookahead: Int
    private let lookbehind = 6

    /// Index of the next script token we expect to hear.
    private(set) var cursor: Int = 0

    /// How many recent spoken words take part in a match.
    private let windowSize = 5

    init(tokens: [String], lookahead: Int) {
        self.tokens = tokens
        self.lookahead = max(8, lookahead)
    }

    var isEmpty: Bool { tokens.isEmpty }

    mutating func reset() {
        cursor = 0
    }

    /// Feed the tail of the live transcript. Returns the matched script token index, if any.
    mutating func consume(spoken: [String]) -> Int? {
        guard !tokens.isEmpty else { return nil }
        let tail = Array(spoken.suffix(windowSize))
        guard !tail.isEmpty else { return nil }

        let lower = max(0, cursor - lookbehind)
        let upper = min(tokens.count, cursor + lookahead)
        guard lower < upper else { return nil }

        var bestScore = 0.0
        var bestIndex: Int?

        for candidate in lower..<upper {
            let score = score(candidate: candidate, tail: tail)
            // Prefer forward progress when two positions score the same.
            if score > bestScore {
                bestScore = score
                bestIndex = candidate
            }
        }

        guard let bestIndex, bestScore >= threshold(for: tail) else { return nil }

        cursor = bestIndex + 1
        return bestIndex
    }

    /// Score treats `candidate` as the script token the speaker just uttered, then
    /// walks backwards comparing older spoken words with earlier script words.
    private func score(candidate: Int, tail: [String]) -> Double {
        var total = 0.0
        for step in 0..<tail.count {
            let spokenIndex = tail.count - 1 - step
            let scriptIndex = candidate - step
            guard scriptIndex >= 0 else { break }
            guard tail[spokenIndex] == tokens[scriptIndex] else { continue }
            // Recent words matter more, and longer words are far less likely to collide.
            let recency = 1.0 / Double(step + 1)
            let weight = tokens[scriptIndex].count >= 4 ? 1.3 : 0.8
            total += recency * weight
        }
        return total
    }

    /// One long word alone is enough; short filler words need corroboration.
    private func threshold(for tail: [String]) -> Double {
        guard let last = tail.last else { return .greatestFiniteMagnitude }
        return last.count >= 5 ? 1.2 : 1.6
    }
}
