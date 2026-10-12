import Foundation

public struct LyricsQuery: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var duration: Double?

    public init(title: String, artist: String, duration: Double?) {
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

public struct LyricsCandidate: Equatable, Sendable {
    public var trackName: String
    public var artistName: String
    public var duration: Double?
    public var synced: String?
    public var plain: String?
    public var instrumental: Bool

    public init(
        trackName: String,
        artistName: String,
        duration: Double?,
        synced: String? = nil,
        plain: String? = nil,
        instrumental: Bool = false
    ) {
        self.trackName = trackName
        self.artistName = artistName
        self.duration = duration
        self.synced = synced
        self.plain = plain
        self.instrumental = instrumental
    }
}

public enum LyricsVerdict: Equatable, Sendable {
    case accepted(kind: LyricsKind, score: Double)
    case rejected(String)

    public var isAccepted: Bool {
        if case .accepted = self {
            return true
        }
        return false
    }
}

public enum LyricsVerifier {
    public static let durationTolerance = 2.0
    public static let titleThreshold = 0.9
    public static let artistThreshold = 0.88
    public static let timelineSlack = 3.0

    public static func isGarbled(_ text: String) -> Bool {
        if text.unicodeScalars.contains(where: { $0.value == 0xFFFD }) {
            return true
        }
        let visible = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        if visible.isEmpty {
            return true
        }
        let questions = visible.filter { $0 == "?" }.count
        return Double(questions) / Double(visible.count) > 0.12
    }

    public static func timelineEnd(of lines: [LyricLine]) -> Double {
        lines.map { $0.time }.max() ?? 0
    }

    public static func verify(_ candidate: LyricsCandidate, against query: LyricsQuery) -> LyricsVerdict {
        if candidate.instrumental {
            return .rejected("instrumental")
        }
        let syncedLines = candidate.synced.map { LRCParser.parse($0) } ?? []
        let plain = (candidate.plain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if syncedLines.isEmpty && plain.isEmpty {
            return .rejected("empty")
        }
        guard let wanted = query.duration, let got = candidate.duration else {
            return .rejected("no-duration")
        }
        if abs(wanted - got) > durationTolerance {
            return .rejected("duration")
        }
        let titleScore = TextMatching.titleRatio(candidate.trackName, query.title)
        if titleScore < titleThreshold {
            return .rejected("title")
        }
        let artistScore = TextMatching.artistRatio(candidate.artistName, query.artist)
        if artistScore < artistThreshold {
            return .rejected("artist")
        }
        if !syncedLines.isEmpty {
            if timelineEnd(of: syncedLines) > wanted + timelineSlack {
                return .rejected("timeline")
            }
            if isGarbled(LRCParser.plainText(from: syncedLines)) {
                return .rejected("garbled")
            }
            let score = (titleScore + artistScore) / 2 - abs(wanted - got) * 0.01
            return .accepted(kind: LRCParser.kind(of: syncedLines), score: score)
        }
        if isGarbled(plain) {
            return .rejected("garbled")
        }
        let score = (titleScore + artistScore) / 2 - abs(wanted - got) * 0.01 - 0.5
        return .accepted(kind: .plain, score: score)
    }

    public static func best(
        of candidates: [LyricsCandidate],
        for query: LyricsQuery
    ) -> (candidate: LyricsCandidate, kind: LyricsKind)? {
        var winner: (LyricsCandidate, LyricsKind, Double)?
        for candidate in candidates {
            guard case let .accepted(kind, score) = verify(candidate, against: query) else { continue }
            let boosted = score + rank(kind)
            if winner == nil || boosted > winner!.2 {
                winner = (candidate, kind, boosted)
            }
        }
        return winner.map { ($0.0, $0.1) }
    }

    private static func rank(_ kind: LyricsKind) -> Double {
        switch kind {
        case .wordSynced: return 2
        case .lineSynced: return 1
        case .plain: return 0
        case .none: return -1
        }
    }
}
