import Foundation

struct TrackRecord: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var title: String
    var artist: String
    var album: String?
    var albumArtist: String?
    var trackNumber: Int?
    var discNumber: Int?
    var year: Int?
    var genre: String?
    var durationMs: Int
    var format: String
    var bitrateKbps: Int?
    var sampleRate: Int?
    var bitDepth: Int?
    var fileName: String
    var fileSize: Int64
    var fileHash: String?
    var coverName: String?
    var motionName: String?
    var motion3x4Name: String?
    var isFavorite: Bool
    var playCount: Int
    var lastPlayedAt: Date?
    var addedAt: Date
    var siteId: String?
    var bpm: Int?
    var palette: String?
    var lyricsKind: String?
    var lyricsSource: String?
    var streamURL: URL?
    var losslessURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, albumArtist, trackNumber, discNumber, year, genre
        case durationMs, format, bitrateKbps, sampleRate, bitDepth, fileName, fileSize, fileHash
        case coverName, motionName, motion3x4Name, isFavorite, playCount, lastPlayedAt, addedAt
        case siteId, bpm, palette, lyricsKind, lyricsSource
    }

    var isRemote: Bool {
        streamURL != nil
    }

    var durationSeconds: Double {
        Double(durationMs) / 1000
    }

    var fileURL: URL {
        AppPaths.trackURL(fileName)
    }

    var displayAlbum: String {
        album ?? ""
    }
}

extension TrackRecord {
    static func blank(id: String = UUID().uuidString) -> TrackRecord {
        TrackRecord(
            id: id,
            title: "",
            artist: "",
            durationMs: 0,
            format: "",
            fileName: "",
            fileSize: 0,
            isFavorite: false,
            playCount: 0,
            addedAt: Date()
        )
    }
}
