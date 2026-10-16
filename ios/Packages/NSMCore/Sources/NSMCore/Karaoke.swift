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

    public static let leadSeconds = 0.12
    public static let defaultRate = 4.0
    public static let minRate = 1.8
    public static let maxRate = 9.5
    public static let tightGap = 6.0
    public static let endGap = 0.97
    public static let maxSung = 14.0
    public static let minSung = 0.5

    private static let vowels: Set<Character> = Set("aeiouyаеёиоуыэюяіїєáàâäéèêëíìîïóòôöúùûüæœ")

    private static func isMora(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }

    public static func wordWeight(_ word: String) -> Double {
        var units = 0
        var inVowel = false
        for character in word.lowercased() {
            if vowels.contains(character) {
                if !inVowel {
                    units += 1
                }
                inVowel = true
            } else {
                inVowel = false
            }
            if character.unicodeScalars.contains(where: isMora) {
                units += 1
            }
        }
        return Double(units > 0 ? units : 1) + 0.2
    }

    public static func lineUnits(_ text: String) -> Double {
        text.split(whereSeparator: { $0.isWhitespace }).reduce(0) { total, word in total + wordWeight(String(word)) }
    }

    public static func calibrateRate(_ lines: [LyricLine]) -> Double {
        var rates: [Double] = []
        if lines.count > 1 {
            for index in 0..<(lines.count - 1) {
                let gap = lines[index + 1].time - lines[index].time
                let units = lineUnits(lines[index].text)
                if gap > 0.4 && gap <= tightGap && units >= 3 {
                    rates.append(units / gap)
                }
            }
        }
        if rates.count < 4 {
            return defaultRate
        }
        rates.sort()
        let pick = rates[min(rates.count - 1, Int(Double(rates.count) * 0.8))]
        return min(maxRate, max(minRate, pick))
    }

    public static func planLine(_ line: LyricLine, nextTime: Double?, rate: Double) -> [LyricWord] {
        let parts = line.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if parts.isEmpty {
            return []
        }
        let weights = parts.map(wordWeight)
        let total = weights.reduce(0, +)
        let gap = nextTime.map { max(0.2, $0 - line.time) } ?? Double.infinity
        let sung = min(gap * endGap, max(minSung, min(total / rate, maxSung)))
        var cursor = 0.0
        var result: [LyricWord] = []
        for (index, part) in parts.enumerated() {
            let start = line.time + sung * cursor / total
            cursor += weights[index]
            let end = line.time + sung * cursor / total
            result.append(LyricWord(text: index == parts.count - 1 ? part : part + " ", start: start, end: end))
        }
        return result
    }

    public static func planLines(_ lines: [LyricLine]) -> [LyricLine] {
        let rate = calibrateRate(lines)
        return lines.enumerated().map { index, line in
            if line.hasWordTiming {
                return line
            }
            var planned = line
            planned.words = planLine(line, nextTime: index + 1 < lines.count ? lines[index + 1].time : nil, rate: rate)
            return planned
        }
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

public enum LyricAnimation: String, CaseIterable, Equatable, Sendable {
    case sweep
    case rise
    case blur
    case pop
    case glow
    case hop
    case slide
    case flip

    public static let autoMode = "auto"

    public static func resolve(mode: String, index: Int, seed: Int) -> LyricAnimation {
        if let fixed = LyricAnimation(rawValue: mode) {
            return fixed
        }
        return allCases[(index + seed) % allCases.count]
    }

    public static func seed(for text: String) -> Int {
        var hash: UInt32 = 0
        for unit in text.utf16 {
            hash = hash &* 31 &+ UInt32(unit)
        }
        return Int(hash % UInt32(allCases.count))
    }
}
