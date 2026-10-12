import Foundation

public struct TrackFingerprint: Equatable, Sendable {
    public var id: String
    public var artist: String
    public var title: String
    public var durationMs: Int?
    public var fileHash: String?
    public var format: String
    public var bitrateKbps: Int?

    public init(
        id: String,
        artist: String,
        title: String,
        durationMs: Int? = nil,
        fileHash: String? = nil,
        format: String = "",
        bitrateKbps: Int? = nil
    ) {
        self.id = id
        self.artist = artist
        self.title = title
        self.durationMs = durationMs
        self.fileHash = fileHash
        self.format = format
        self.bitrateKbps = bitrateKbps
    }
}

public enum DuplicateKind: String, Equatable, Sendable {
    case sameFile
    case sameTrack
    case similar
}

public struct DuplicateMatch: Equatable, Sendable {
    public var existingID: String
    public var kind: DuplicateKind
    public var candidateIsBetterQuality: Bool
}

public enum QualityRank {
    private static let lossless: Set<String> = ["flac", "wav", "aiff", "aif", "alac", "ape", "wv", "dsf"]

    public static func score(format: String, bitrateKbps: Int?) -> Int {
        let key = format.lowercased()
        if lossless.contains(key) {
            return 10_000
        }
        return bitrateKbps ?? 128
    }
}

public struct DuplicateIndex: Sendable {
    public static let sameTrackToleranceMs = 2000
    public static let similarToleranceMs = 3000
    public static let similarTitleThreshold = 0.92

    private var byHash: [String: [TrackFingerprint]] = [:]
    private var byKey: [String: [TrackFingerprint]] = [:]
    private var byArtist: [String: [TrackFingerprint]] = [:]

    public init(_ tracks: [TrackFingerprint] = []) {
        for track in tracks {
            add(track)
        }
    }

    private static func key(_ track: TrackFingerprint) -> String {
        TextMatching.artistKey(track.artist) + "|" + TextMatching.titleKey(track.title)
    }

    public mutating func add(_ track: TrackFingerprint) {
        if let hash = track.fileHash, !hash.isEmpty {
            byHash[hash, default: []].append(track)
        }
        byKey[Self.key(track), default: []].append(track)
        byArtist[TextMatching.artistKey(track.artist), default: []].append(track)
    }

    public mutating func remove(id: String) {
        for key in byHash.keys {
            byHash[key]?.removeAll { $0.id == id }
        }
        for key in byKey.keys {
            byKey[key]?.removeAll { $0.id == id }
        }
        for key in byArtist.keys {
            byArtist[key]?.removeAll { $0.id == id }
        }
    }

    private static func closeEnough(_ a: Int?, _ b: Int?, tolerance: Int) -> Bool {
        guard let a, let b else { return true }
        return abs(a - b) <= tolerance
    }

    public func matches(for candidate: TrackFingerprint) -> [DuplicateMatch] {
        var seen = Set<String>()
        var result: [DuplicateMatch] = []
        func better(_ existing: TrackFingerprint) -> Bool {
            QualityRank.score(format: candidate.format, bitrateKbps: candidate.bitrateKbps)
                > QualityRank.score(format: existing.format, bitrateKbps: existing.bitrateKbps)
        }
        if let hash = candidate.fileHash, let hits = byHash[hash] {
            for hit in hits where hit.id != candidate.id && seen.insert(hit.id).inserted {
                result.append(DuplicateMatch(existingID: hit.id, kind: .sameFile, candidateIsBetterQuality: false))
            }
        }
        if let hits = byKey[Self.key(candidate)] {
            for hit in hits where hit.id != candidate.id
                && Self.closeEnough(hit.durationMs, candidate.durationMs, tolerance: Self.sameTrackToleranceMs)
                && seen.insert(hit.id).inserted {
                result.append(DuplicateMatch(existingID: hit.id, kind: .sameTrack, candidateIsBetterQuality: better(hit)))
            }
        }
        if result.isEmpty, let hits = byArtist[TextMatching.artistKey(candidate.artist)] {
            let wantedTitle = TextMatching.titleKey(candidate.title)
            for hit in hits where hit.id != candidate.id
                && Self.closeEnough(hit.durationMs, candidate.durationMs, tolerance: Self.similarToleranceMs)
                && SequenceSimilarity.ratio(TextMatching.titleKey(hit.title), wantedTitle) >= Self.similarTitleThreshold
                && seen.insert(hit.id).inserted {
                result.append(DuplicateMatch(existingID: hit.id, kind: .similar, candidateIsBetterQuality: better(hit)))
            }
        }
        return result
    }
}
