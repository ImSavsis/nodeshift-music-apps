import Foundation
import NSMCore

struct CatalogMatch: Sendable {
    var title: String
    var artist: String
    var album: String?
    var albumArtist: String?
    var trackNumber: Int?
    var discNumber: Int?
    var year: Int?
    var genre: String?
    var isrc: String?
    var coverURL: URL?
    var durationSeconds: Double?
    var source: String
}

struct CatalogQuery: Sendable {
    var title: String
    var artist: String
    var album: String?
    var duration: Double?
}

private struct ITunesResponse: Decodable {
    let results: [ITunesItem]
}

private struct ITunesItem: Decodable {
    let wrapperType: String?
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let trackTimeMillis: Int?
    let trackNumber: Int?
    let discNumber: Int?
    let releaseDate: String?
    let primaryGenreName: String?
    let artworkUrl100: String?
}

private struct DeezerSearch: Decodable {
    let data: [DeezerTrack]
}

private struct DeezerArtist: Decodable {
    let name: String
}

private struct DeezerAlbumRef: Decodable {
    let id: Int?
    let title: String?
    let coverXl: String?
}

private struct DeezerTrack: Decodable {
    let id: Int
    let title: String
    let duration: Int?
    let artist: DeezerArtist
    let album: DeezerAlbumRef?
    let trackPosition: Int?
    let diskNumber: Int?
    let releaseDate: String?
    let isrc: String?
}

private struct DeezerAlbumFull: Decodable {
    struct Genres: Decodable {
        struct Genre: Decodable {
            let name: String
        }

        let data: [Genre]
    }

    let releaseDate: String?
    let genres: Genres?
}

enum CatalogClient {
    static func lookup(_ query: CatalogQuery) async -> CatalogMatch? {
        if let apple = await iTunes(query) {
            if apple.album != nil {
                return apple
            }
        }
        if let deezer = await deezer(query) {
            return deezer
        }
        return await iTunes(query)
    }

    static func score(query: CatalogQuery, title: String, artist: String, duration: Double?) -> Double? {
        let titleScore = TextMatching.titleRatio(query.title, title)
        let artistKnown = !query.artist.isEmpty
        if titleScore < (artistKnown ? 0.85 : 0.95) {
            return nil
        }
        var artistScore = 1.0
        if artistKnown {
            artistScore = TextMatching.artistRatio(query.artist, artist)
            if artistScore < 0.8 {
                return nil
            }
        }
        var penalty = 0.0
        if let wanted = query.duration, let got = duration {
            let diff = abs(wanted - got)
            if diff > (artistKnown ? 4 : 2) {
                return nil
            }
            penalty = diff * 0.02
        }
        return titleScore + artistScore - penalty
    }

    static func year(from text: String?) -> Int? {
        guard let text, text.count >= 4 else { return nil }
        return Int(text.prefix(4))
    }

    static func artworkURL(_ small: String?) -> URL? {
        guard let small else { return nil }
        let large = small.replacingOccurrences(of: "100x100bb", with: "1400x1400bb")
        return URL(string: large)
    }

    static func searchTerm(_ query: CatalogQuery) -> String {
        let artist = TextMatching.stripFeaturing(query.artist)
        let title = TextMatching.stripFeaturing(query.title)
        return [artist, title].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func iTunes(_ query: CatalogQuery) async -> CatalogMatch? {
        for country in ["us", "ru"] {
            await RateLimiter.shared.wait("itunes", interval: 3.2)
            guard let url = Net.components("https://itunes.apple.com/search", [
                "term": searchTerm(query),
                "media": "music",
                "entity": "song",
                "limit": "10",
                "country": country,
            ]) else { continue }
            guard let response = try? await Net.json(url, as: ITunesResponse.self) else { continue }
            var best: (ITunesItem, Double)?
            for item in response.results where item.wrapperType == "track" {
                guard let title = item.trackName, let artist = item.artistName else { continue }
                let duration = item.trackTimeMillis.map { Double($0) / 1000 }
                guard let value = score(query: query, title: title, artist: artist, duration: duration) else { continue }
                if best == nil || value > best!.1 {
                    best = (item, value)
                }
            }
            if let (item, _) = best {
                return CatalogMatch(
                    title: item.trackName ?? query.title,
                    artist: item.artistName ?? query.artist,
                    album: item.collectionName,
                    albumArtist: nil,
                    trackNumber: item.trackNumber,
                    discNumber: item.discNumber,
                    year: year(from: item.releaseDate),
                    genre: item.primaryGenreName,
                    isrc: nil,
                    coverURL: artworkURL(item.artworkUrl100),
                    durationSeconds: item.trackTimeMillis.map { Double($0) / 1000 },
                    source: "itunes"
                )
            }
        }
        return nil
    }

    static func deezer(_ query: CatalogQuery) async -> CatalogMatch? {
        await RateLimiter.shared.wait("deezer", interval: 0.25)
        let artist = TextMatching.stripFeaturing(query.artist)
        let title = TextMatching.stripFeaturing(query.title)
        let term = artist.isEmpty ? title : "artist:\"\(artist)\" track:\"\(title)\""
        guard let url = Net.components("https://api.deezer.com/search", ["q": term, "limit": "10"]) else {
            return nil
        }
        guard let response = try? await Net.json(url, as: DeezerSearch.self, snakeCase: true) else {
            return nil
        }
        var best: (DeezerTrack, Double)?
        for item in response.data {
            guard let value = score(query: query, title: item.title, artist: item.artist.name, duration: item.duration.map(Double.init)) else {
                continue
            }
            if best == nil || value > best!.1 {
                best = (item, value)
            }
        }
        guard let (candidate, _) = best else { return nil }
        await RateLimiter.shared.wait("deezer", interval: 0.25)
        var full = candidate
        if let detailURL = URL(string: "https://api.deezer.com/track/\(candidate.id)"),
           let detail = try? await Net.json(detailURL, as: DeezerTrack.self, snakeCase: true) {
            full = detail
        }
        var genre: String?
        var releaseDate = full.releaseDate
        if let albumID = full.album?.id ?? candidate.album?.id,
           let albumURL = URL(string: "https://api.deezer.com/album/\(albumID)") {
            await RateLimiter.shared.wait("deezer", interval: 0.25)
            if let album = try? await Net.json(albumURL, as: DeezerAlbumFull.self, snakeCase: true) {
                genre = album.genres?.data.first?.name
                releaseDate = releaseDate ?? album.releaseDate
            }
        }
        return CatalogMatch(
            title: full.title,
            artist: full.artist.name,
            album: full.album?.title ?? candidate.album?.title,
            albumArtist: nil,
            trackNumber: full.trackPosition,
            discNumber: full.diskNumber,
            year: year(from: releaseDate),
            genre: genre,
            isrc: full.isrc,
            coverURL: (full.album?.coverXl ?? candidate.album?.coverXl).flatMap { URL(string: $0) },
            durationSeconds: full.duration.map(Double.init),
            source: "deezer"
        )
    }
}
