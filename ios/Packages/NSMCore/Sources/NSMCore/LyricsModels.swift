import Foundation

public struct LyricWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct LyricLine: Equatable, Sendable {
    public var time: Double
    public var text: String
    public var words: [LyricWord]?

    public init(time: Double, text: String, words: [LyricWord]? = nil) {
        self.time = time
        self.text = text
        self.words = words
    }

    public var hasWordTiming: Bool {
        words?.isEmpty == false
    }
}

public enum LyricsKind: String, Equatable, Sendable {
    case wordSynced
    case lineSynced
    case plain
    case none
}
