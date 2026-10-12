import Foundation

public struct ParsedName: Equatable, Sendable {
    public var disc: Int?
    public var track: Int?
    public var artist: String?
    public var title: String?

    public init(disc: Int? = nil, track: Int? = nil, artist: String? = nil, title: String? = nil) {
        self.disc = disc
        self.track = track
        self.artist = artist
        self.title = title
    }
}

public enum FilenameParser {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let extensionPattern = regex(#"\.(mp3|flac|wav|ogg|opus|m4a|aac|aiff?|wma)$"#)
    private static let junkPattern = regex(#"\s*[\[\(](?:flac|mp3|320\s*kbps|320|hq|hd|lossless|official\s*(?:audio|video|music\s*video|lyric\s*video))[\]\)]\s*"#)
    private static let sitePattern = regex(#"\s*[\[\(]?(?:www\.)?[a-z0-9-]+\.(?:com|net|org|ru|me|io|fm)[\]\)]?\s*$"#)
    private static let dashPattern = regex(#"(?:\s+[-–—]\s+|\s*[-–—]\s+|\s+[-–—]\s*)"#)
    private static let discTrackPattern = regex(#"^(\d{1,2})[-.](\d{2,3})(?:\s*(?:[-.)_]|\s[-–—]\s)\s*|\s+)"#)
    private static let strongPattern = regex(#"^(\d{1,3})(?:\s*[-.)_]\s*|\s[-–—]\s)"#)
    private static let weakPattern = regex(#"^(\d{1,3})\s+(?=\D)"#)

    private struct Lead {
        let value: Int
        let raw: String
        let rest: String
        let strong: Bool
    }

    private static func fullRange(_ text: String) -> NSRange {
        NSRange(text.startIndex..<text.endIndex, in: text)
    }

    private static func replace(_ re: NSRegularExpression, in text: String, with template: String) -> String {
        re.stringByReplacingMatches(in: text, options: [], range: fullRange(text), withTemplate: template)
    }

    private static func firstMatch(_ re: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        re.firstMatch(in: text, options: [], range: fullRange(text))
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func remainder(_ match: NSTextCheckingResult, in text: String) -> String {
        guard let range = Range(match.range, in: text) else { return text }
        return String(text[range.upperBound...])
    }

    private static func split(_ re: NSRegularExpression, _ text: String) -> [String] {
        var parts: [String] = []
        var cursor = text.startIndex
        for match in re.matches(in: text, options: [], range: fullRange(text)) {
            guard let range = Range(match.range, in: text) else { continue }
            parts.append(String(text[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }
        parts.append(String(text[cursor...]))
        return parts
    }

    private static func nonEmptyParts(_ text: String) -> [String] {
        split(dashPattern, text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func clean(_ stem: String) -> String {
        var text = stem.precomposedStringWithCanonicalMapping
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(" ") && text.filter({ $0 == "_" }).count >= 2 {
            text = text.replacingOccurrences(of: "_", with: " ")
        }
        text = replace(junkPattern, in: text, with: " ")
        text = replace(sitePattern, in: text, with: "")
        return collapse(text)
    }

    static func stem(_ name: String) -> String {
        clean(replace(extensionPattern, in: name, with: ""))
    }

    private static func lead(_ text: String) -> Lead? {
        if let match = firstMatch(strongPattern, in: text),
           let raw = group(match, 1, in: text),
           let value = Int(raw) {
            return Lead(value: value, raw: raw, rest: remainder(match, in: text), strong: true)
        }
        if let match = firstMatch(weakPattern, in: text),
           let raw = group(match, 1, in: text),
           let value = Int(raw) {
            return Lead(value: value, raw: raw, rest: remainder(match, in: text), strong: false)
        }
        return nil
    }

    public static func isNumberedBatch(_ names: [String]) -> Bool {
        let texts = names.map(stem)
        var found: [Int?] = []
        for text in texts {
            if firstMatch(discTrackPattern, in: text) != nil {
                found.append(nil)
                continue
            }
            if let info = lead(text) {
                found.append(info.value)
            }
        }
        if Double(found.count) < Double(texts.count) * 0.8 || texts.count < 3 {
            return false
        }
        let plain = found.compactMap { $0 }
        return !plain.isEmpty
            && plain.allSatisfy { (1...99).contains($0) }
            && Set(plain).count == plain.count
    }

    public static func parse(_ name: String, numberedBatch: Bool) -> ParsedName {
        var text = stem(name)
        var result = ParsedName()
        if let match = firstMatch(discTrackPattern, in: text),
           let disc = group(match, 1, in: text),
           let track = group(match, 2, in: text) {
            result.disc = Int(disc)
            result.track = Int(track)
            text = remainder(match, in: text)
        } else if let info = lead(text) {
            let padded = info.raw.count == 2 && info.raw.hasPrefix("0")
            let threePart = info.strong && nonEmptyParts(info.rest).count >= 2
            if padded || threePart || numberedBatch {
                result.track = info.value
                text = info.rest
            }
        }
        let parts = nonEmptyParts(text)
        if parts.count >= 2 {
            result.artist = parts[0]
            result.title = parts.dropFirst().joined(separator: " - ")
        } else if let first = parts.first {
            result.title = first
        }
        return result
    }

    public static func parseBatch(_ names: [String]) -> [ParsedName] {
        let numbered = isNumberedBatch(names)
        return names.map { parse($0, numberedBatch: numbered) }
    }
}
