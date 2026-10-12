import Foundation
import GRDB

struct PlaylistRecord: Identifiable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "playlist"

    var id: String
    var name: String
    var coverName: String?
    var siteId: String?
    var createdAt: Date
}

struct PlaylistTrackRecord: Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "playlistTrack"

    var playlistId: String
    var trackId: String
    var position: Int
}

struct LyricsRecord: Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "lyrics"

    var trackId: String
    var kind: String
    var source: String
    var lrc: String?
    var plain: String?
    var checkedAt: Date
}

struct WishlistRecord: Identifiable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "wishlist"

    var id: String
    var title: String
    var artist: String
    var album: String?
    var coverName: String?
    var addedAt: Date
}

extension TrackRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "track"
}

final class AppDatabase: @unchecked Sendable {
    let queue: DatabaseQueue

    init(path: String?) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        if let path {
            queue = try DatabaseQueue(path: path, configuration: configuration)
        } else {
            queue = try DatabaseQueue(configuration: configuration)
        }
        try Self.migrator.migrate(queue)
    }

    static func open() -> AppDatabase {
        if let database = try? AppDatabase(path: AppPaths.databaseURL.path) {
            return database
        }
        return try! AppDatabase(path: nil)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "track") { table in
                table.primaryKey("id", .text)
                table.column("title", .text).notNull()
                table.column("artist", .text).notNull()
                table.column("album", .text)
                table.column("albumArtist", .text)
                table.column("trackNumber", .integer)
                table.column("discNumber", .integer)
                table.column("year", .integer)
                table.column("genre", .text)
                table.column("durationMs", .integer).notNull()
                table.column("format", .text).notNull()
                table.column("bitrateKbps", .integer)
                table.column("sampleRate", .integer)
                table.column("bitDepth", .integer)
                table.column("fileName", .text).notNull()
                table.column("fileSize", .integer).notNull()
                table.column("fileHash", .text)
                table.column("coverName", .text)
                table.column("motionName", .text)
                table.column("motion3x4Name", .text)
                table.column("isFavorite", .boolean).notNull().defaults(to: false)
                table.column("playCount", .integer).notNull().defaults(to: 0)
                table.column("lastPlayedAt", .datetime)
                table.column("addedAt", .datetime).notNull()
                table.column("siteId", .text)
                table.column("bpm", .integer)
                table.column("palette", .text)
                table.column("lyricsKind", .text)
                table.column("lyricsSource", .text)
            }
            try db.create(index: "track_hash", on: "track", columns: ["fileHash"])
            try db.create(index: "track_site", on: "track", columns: ["siteId"])
            try db.create(table: "playlist") { table in
                table.primaryKey("id", .text)
                table.column("name", .text).notNull()
                table.column("coverName", .text)
                table.column("siteId", .text)
                table.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "playlistTrack") { table in
                table.column("playlistId", .text).notNull().references("playlist", onDelete: .cascade)
                table.column("trackId", .text).notNull().references("track", onDelete: .cascade)
                table.column("position", .integer).notNull()
                table.primaryKey(["playlistId", "trackId"])
            }
            try db.create(table: "lyrics") { table in
                table.primaryKey("trackId", .text).references("track", onDelete: .cascade)
                table.column("kind", .text).notNull()
                table.column("source", .text).notNull()
                table.column("lrc", .text)
                table.column("plain", .text)
                table.column("checkedAt", .datetime).notNull()
            }
            try db.create(table: "wishlist") { table in
                table.primaryKey("id", .text)
                table.column("title", .text).notNull()
                table.column("artist", .text).notNull()
                table.column("album", .text)
                table.column("coverName", .text)
                table.column("addedAt", .datetime).notNull()
            }
        }
        return migrator
    }

    func allTracks() throws -> [TrackRecord] {
        try queue.read { db in
            try TrackRecord.fetchAll(db)
        }
    }

    func save(_ track: TrackRecord) throws {
        try queue.write { db in
            try track.save(db)
        }
    }

    func deleteTrack(id: String) throws {
        _ = try queue.write { db in
            try TrackRecord.deleteOne(db, key: id)
        }
    }

    func setFavorite(id: String, value: Bool) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE track SET isFavorite = ? WHERE id = ?", arguments: [value, id])
        }
    }

    func linkSite(trackID: String, siteID: String) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE track SET siteId = ? WHERE id = ?", arguments: [siteID, trackID])
        }
    }

    func markPlayed(id: String, at date: Date) throws {
        try queue.write { db in
            try db.execute(
                sql: "UPDATE track SET playCount = playCount + 1, lastPlayedAt = ? WHERE id = ?",
                arguments: [date, id]
            )
        }
    }

    func lyrics(trackId: String) throws -> LyricsRecord? {
        try queue.read { db in
            try LyricsRecord.fetchOne(db, key: trackId)
        }
    }

    func save(_ lyrics: LyricsRecord) throws {
        try queue.write { db in
            try lyrics.save(db)
        }
    }

    func playlists() throws -> [PlaylistRecord] {
        try queue.read { db in
            try PlaylistRecord.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func trackIDs(playlist id: String) throws -> [String] {
        try queue.read { db in
            try PlaylistTrackRecord
                .filter(Column("playlistId") == id)
                .order(Column("position"))
                .fetchAll(db)
                .map { $0.trackId }
        }
    }

    func save(_ playlist: PlaylistRecord, trackIDs: [String]) throws {
        try queue.write { db in
            try playlist.save(db)
            try db.execute(sql: "DELETE FROM playlistTrack WHERE playlistId = ?", arguments: [playlist.id])
            for (index, trackId) in trackIDs.enumerated() {
                try PlaylistTrackRecord(playlistId: playlist.id, trackId: trackId, position: index).insert(db)
            }
        }
    }

    func deletePlaylist(id: String) throws {
        _ = try queue.write { db in
            try PlaylistRecord.deleteOne(db, key: id)
        }
    }
}
