import Foundation

public struct SyntheticWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double
}

public enum Karaoke {
    public static let maxLineSeconds = 7.0
    public static let minSpan = 0.6
    public static let spanFactor = 0.92

    public static func syntheticWords(for text: String) -> [SyntheticWord] {
        let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let weights = parts.map { Double($0.utf16.count) + 1.5 }
        let sum = weights.reduce(0, +)
        let total = sum == 0 ? 1.0 : sum
        var cursor = 0.0
        var result: [SyntheticWord] = []
        for (index, part) in parts.enumerated() {
            let start = cursor / total
            cursor += weights[index]
            result.append(SyntheticWord(text: part, start: start, end: cursor / total))
        }
        return result
    }

    public static func span(lineTime: Double, nextTime: Double?) -> Double {
        let next = nextTime ?? (lineTime + maxLineSeconds)
        return max(minSpan, min(next - lineTime, maxLineSeconds) * spanFactor)
    }

    public static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    public static func syntheticFills(text: String, lineTime: Double, nextTime: Double?, at time: Double) -> [Double] {
        let words = syntheticWords(for: text)
        let progress = clamp01((time - lineTime) / span(lineTime: lineTime, nextTime: nextTime))
        return words.map { word in
            let width = word.end - word.start
            return width <= 0 ? 1 : clamp01((progress - word.start) / width)
        }
    }

    public static func timedFills(words: [LyricWord], at time: Double) -> [Double] {
        words.map { word in
            let width = max(word.end - word.start, 0.001)
            return clamp01((time - word.start) / width)
        }
    }

    public static func fills(for line: LyricLine, nextTime: Double?, at time: Double) -> [Double] {
        if let words = line.words, !words.isEmpty {
            return timedFills(words: words, at: time)
        }
        return syntheticFills(text: line.text, lineTime: line.time, nextTime: nextTime, at: time)
    }

    public static func activeIndex(in lines: [LyricLine], at time: Double) -> Int {
        var low = 0
        var high = lines.count - 1
        var found = -1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    public struct LineStyle: Equatable, Sendable {
        public var opacity: Double
        public var scale: Double
        public var blur: Double
    }

    public static func style(index: Int, active: Int) -> LineStyle {
        if index == active {
            return LineStyle(opacity: 1, scale: 1, blur: 0)
        }
        let distance = Double(abs(index - active))
        if index < active {
            return LineStyle(opacity: 0.38, scale: 0.93, blur: min(distance, 5) * 0.55)
        }
        return LineStyle(opacity: 0.30, scale: 0.93, blur: min(distance, 5) * 0.7)
    }
}
