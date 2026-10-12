import Foundation

public enum TextMatching {
    private static let bracketPattern = try! NSRegularExpression(pattern: #"[\(\[][^\)\]]*[\)\]]"#)
    private static let nonWordPattern = try! NSRegularExpression(pattern: #"[^\w\s]"#)
    private static let featuringPattern = try! NSRegularExpression(
        pattern: #"\s*[\(\[]?\s*\b(?:feat|ft|featuring)\b\.?\s+.*$"#,
        options: [.caseInsensitive]
    )
    private static let artistSplitPattern = try! NSRegularExpression(
        pattern: #"\s*(?:,|;|&|/|\bx\b|×|\band\b|\bи\b)\s*"#,
        options: [.caseInsensitive]
    )

    private static func replace(_ re: NSRegularExpression, in text: String, with template: String) -> String {
        re.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: template
        )
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        let withoutBrackets = replace(bracketPattern, in: folded, with: " ")
        return collapse(replace(nonWordPattern, in: withoutBrackets, with: " "))
    }

    public static func stripFeaturing(_ text: String) -> String {
        collapse(replace(featuringPattern, in: text, with: ""))
    }

    public static func titleKey(_ title: String) -> String {
        normalize(stripFeaturing(title))
    }

    public static func artistKey(_ artist: String) -> String {
        normalize(stripFeaturing(artist))
    }

    public static func artistParts(_ artist: String) -> [String] {
        let base = stripFeaturing(artist)
        var parts: [String] = []
        var cursor = base.startIndex
        for match in artistSplitPattern.matches(in: base, options: [], range: NSRange(base.startIndex..<base.endIndex, in: base)) {
            guard let range = Range(match.range, in: base) else { continue }
            parts.append(String(base[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }
        parts.append(String(base[cursor...]))
        return parts.map(normalize).filter { !$0.isEmpty }
    }

    public static func titleRatio(_ a: String, _ b: String) -> Double {
        SequenceSimilarity.ratio(titleKey(a), titleKey(b))
    }

    public static func artistRatio(_ a: String, _ b: String) -> Double {
        let whole = SequenceSimilarity.ratio(artistKey(a), artistKey(b))
        if whole >= 0.999 {
            return whole
        }
        var best = whole
        let left = artistParts(a)
        let right = artistParts(b)
        for x in left {
            for y in right {
                best = max(best, SequenceSimilarity.ratio(x, y))
            }
        }
        return best
    }

    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}
