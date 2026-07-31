import Foundation

/// A parsed script: the display lines the prompter renders, plus a flat list of
/// spoken tokens used by voice tracking. Stage directions in brackets — `[Pause]`,
/// `(beat)` — are shown but never tokenised, so the matcher does not stall on them.
struct ScriptModel {
    struct Line: Identifiable {
        let id: Int
        let text: String
        let isDirection: Bool
        /// Range into `tokens`. Empty for blank lines and stage directions.
        let tokenRange: Range<Int>
    }

    let lines: [Line]
    let tokens: [String]

    init(script: String) {
        var lines: [Line] = []
        var tokens: [String] = []

        for (index, raw) in script.components(separatedBy: .newlines).enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let isDirection = Self.directionOnly(trimmed)
            let start = tokens.count
            if !isDirection {
                tokens.append(contentsOf: Self.tokenize(trimmed))
            }
            lines.append(
                Line(id: index, text: raw, isDirection: isDirection, tokenRange: start..<tokens.count)
            )
        }

        self.lines = lines
        self.tokens = tokens
    }

    var isEmpty: Bool { tokens.isEmpty }

    /// The display line that owns a given token, or nil past the end.
    func lineIndex(forToken token: Int) -> Int? {
        lines.first(where: { $0.tokenRange.contains(token) })?.id
    }

    /// 0...1 position of a token inside its own line, for sub-line scroll smoothing.
    func fraction(ofToken token: Int) -> Double {
        guard let line = lines.first(where: { $0.tokenRange.contains(token) }) else { return 0 }
        let count = line.tokenRange.count
        guard count > 1 else { return 0 }
        return Double(token - line.tokenRange.lowerBound) / Double(count)
    }

    // MARK: Parsing

    /// A line made up only of `[...]` or `(...)` fragments is a stage direction.
    private static func directionOnly(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let stripped = text
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty && text.contains(where: { $0 == "[" || $0 == "(" })
    }

    static func tokenize(_ text: String) -> [String] {
        let withoutDirections = text
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)

        return withoutDirections
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
