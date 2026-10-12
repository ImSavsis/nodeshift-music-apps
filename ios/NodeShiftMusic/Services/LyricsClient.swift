import Foundation
import NSMCore

private struct LrclibItem: Decodable {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

struct FoundLyrics: Sendable {
    var kind: LyricsKind
    var lrc: String?
    var plain: String?
    var source: String
}

enum LyricsClient {
    private static let base = "https://lrclib.net/api"

    static func fetch(title: String, artist: String, album: String?, duration: Double?) async -> FoundLyrics? {
        let query = LyricsQuery(title: title, artist: artist, duration: duration)
        var candidates: [LyricsCandidate] = []
        if let exact = await get(title: title, artist: artist, album: album, duration: duration) {
            candidates.append(exact)
        }
        if LyricsVerifier.best(of: candidates, for: query) == nil {
            candidates.append(contentsOf: await search(["track_name": title, "artist_name": artist]))
            if LyricsVerifier.best(of: candidates, for: query) == nil {
                candidates.append(contentsOf: await search(["q": "\(artist) \(title)"]))
            }
        }
        guard let winner = LyricsVerifier.best(of: candidates, for: query) else {
            return nil
        }
        let candidate = winner.candidate
        if winner.kind == .plain {
            return FoundLyrics(kind: .plain, lrc: nil, plain: candidate.plain, source: "lrclib-verified")
        }
        return FoundLyrics(
            kind: winner.kind,
            lrc: candidate.synced,
            plain: candidate.plain,
            source: "lrclib-verified"
        )
    }

    private static func candidate(from item: LrclibItem) -> LyricsCandidate? {
        guard let name = item.trackName, let artist = item.artistName else { return nil }
        return LyricsCandidate(
            trackName: name,
            artistName: artist,
            duration: item.duration,
            synced: item.syncedLyrics,
            plain: item.plainLyrics,
            instrumental: item.instrumental ?? false
        )
    }

    private static func get(title: String, artist: String, album: String?, duration: Double?) async -> LyricsCandidate? {
        var items = ["track_name": title, "artist_name": artist]
        if let album, !album.isEmpty {
            items["album_name"] = album
        }
        if let duration {
            items["duration"] = String(Int(duration.rounded()))
        }
        guard let url = Net.components("\(base)/get", items) else { return nil }
        await RateLimiter.shared.wait("lrclib", interval: 0.35)
        guard let item = try? await Net.json(url, as: LrclibItem.self) else { return nil }
        return candidate(from: item)
    }

    private static func search(_ items: [String: String]) async -> [LyricsCandidate] {
        guard let url = Net.components("\(base)/search", items) else { return [] }
        await RateLimiter.shared.wait("lrclib", interval: 0.35)
        guard let list = try? await Net.json(url, as: [LrclibItem].self) else { return [] }
        return list.compactMap { candidate(from: $0) }
    }
}
