import Foundation

public enum LRCParser {
    private static let lineTagPattern = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2}(?:[.:]\d{1,3})?)\]"#)
    private static let wordTagPattern = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{2}(?:[.:]\d{1,3})?)>"#)
    private static let offsetPattern = try! NSRegularExpression(pattern: #"^\s*\[offset:\s*([+-]?\d+)\s*\]\s*$"#, options: [.caseInsensitive])

    private static func seconds(minutes: String, seconds: String) -> Double? {
        guard let m = Double(minutes), let s = Double(seconds.replacingOccurrences(of: ":", with: ".")) else {
            return nil
        }
        return m * 60 + s
    }

    private static func range(_ text: String) -> NSRange {
        NSRange(text.startIndex..<text.endIndex, in: text)
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard let r = Range(match.range(at: index), in: text) else { return nil }
        return String(text[r])
    }

    public static func parse(_ lrc: String) -> [LyricLine] {
        var offset = 0.0
        var result: [LyricLine] = []
        let rawLines = lrc.components(separatedBy: .newlines)
        for raw in rawLines {
            if let match = offsetPattern.firstMatch(in: raw, options: [], range: range(raw)),
               let value = group(match, 1, in: raw),
               let ms = Double(value) {
                offset = ms / 1000
                continue
            }
            let tags = lineTagPattern.matches(in: raw, options: [], range: range(raw))
            if tags.isEmpty {
                continue
            }
            let body = lineTagPattern.stringByReplacingMatches(in: raw, options: [], range: range(raw), withTemplate: "")
            let times: [Double] = tags.compactMap { tag in
                guard let m = group(tag, 1, in: raw), let s = group(tag, 2, in: raw) else { return nil }
                return seconds(minutes: m, seconds: s)
            }
            let parsedWords = parseWords(body)
            let plainText = wordTagPattern
                .stringByReplacingMatches(in: body, options: [], range: range(body), withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if plainText.isEmpty {
                continue
            }
            for time in times {
                let shifted = time - offset
                result.append(LyricLine(time: shifted, text: plainText, words: parsedWords))
            }
        }
        let indexed = result.enumerated().sorted { left, right in
            if left.element.time != right.element.time {
                return left.element.time < right.element.time
            }
            return left.offset < right.offset
        }
        var lines = indexed.map { $0.element }
        applyWordEnds(&lines)
        return lines
    }

    private static func parseWords(_ body: String) -> [LyricWord]? {
        let tags = wordTagPattern.matches(in: body, options: [], range: range(body))
        if tags.isEmpty {
            return nil
        }
        var words: [LyricWord] = []
        for (index, tag) in tags.enumerated() {
            guard let m = group(tag, 1, in: body),
                  let s = group(tag, 2, in: body),
                  let start = seconds(minutes: m, seconds: s),
                  let tagRange = Range(tag.range, in: body) else { continue }
            let nextLower: String.Index
            if index + 1 < tags.count, let nextRange = Range(tags[index + 1].range, in: body) {
                nextLower = nextRange.lowerBound
            } else {
                nextLower = body.endIndex
            }
            let segment = String(body[tagRange.upperBound..<nextLower])
            if segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let last = words.indices.last {
                    words[last].end = start
                }
                continue
            }
            words.append(LyricWord(text: segment, start: start, end: start))
        }
        if words.isEmpty {
            return nil
        }
        for index in words.indices where index + 1 < words.count {
            if words[index].end <= words[index].start {
                words[index].end = words[index + 1].start
            }
        }
        return words
    }

    private static func applyWordEnds(_ lines: inout [LyricLine]) {
        for index in lines.indices {
            guard var words = lines[index].words, !words.isEmpty else { continue }
            let lineEnd: Double
            if index + 1 < lines.count {
                lineEnd = lines[index + 1].time
            } else {
                lineEnd = (words.last?.start ?? lines[index].time) + 1.5
            }
            if let last = words.indices.last, words[last].end <= words[last].start {
                words[last].end = max(lineEnd, words[last].start + 0.3)
            }
            lines[index].words = words
        }
    }

    public static func kind(of lines: [LyricLine]) -> LyricsKind {
        if lines.isEmpty {
            return .none
        }
        let timed = lines.filter { $0.hasWordTiming }.count
        if Double(timed) >= Double(lines.count) * 0.6 {
            return .wordSynced
        }
        return .lineSynced
    }

    public static func plainText(from lines: [LyricLine]) -> String {
        lines.map { $0.text }.joined(separator: "\n")
    }
}
