package space.nodeshift.music.data

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class AppDatabase(context: Context, name: String? = AppPaths.databaseFile.path) :
    SQLiteOpenHelper(context, name, null, 1) {

    private val version = MutableStateFlow(0L)
    val changes: StateFlow<Long> = version

    override fun onConfigure(db: SQLiteDatabase) {
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE track (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT,
                albumArtist TEXT,
                trackNumber INTEGER,
                discNumber INTEGER,
                year INTEGER,
                genre TEXT,
                durationMs INTEGER NOT NULL,
                format TEXT NOT NULL,
                bitrateKbps INTEGER,
                sampleRate INTEGER,
                bitDepth INTEGER,
                fileName TEXT NOT NULL,
                fileSize INTEGER NOT NULL,
                fileHash TEXT,
                coverName TEXT,
                motionName TEXT,
                motion3x4Name TEXT,
                isFavorite INTEGER NOT NULL DEFAULT 0,
                playCount INTEGER NOT NULL DEFAULT 0,
                lastPlayedAt INTEGER,
                addedAt INTEGER NOT NULL,
                siteId TEXT,
                bpm INTEGER,
                palette TEXT,
                lyricsKind TEXT,
                lyricsSource TEXT
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX track_hash ON track(fileHash)")
        db.execSQL("CREATE INDEX track_site ON track(siteId)")
        db.execSQL(
            """
            CREATE TABLE playlist (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                coverName TEXT,
                siteId TEXT,
                createdAt INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE playlistTrack (
                playlistId TEXT NOT NULL REFERENCES playlist(id) ON DELETE CASCADE,
                trackId TEXT NOT NULL REFERENCES track(id) ON DELETE CASCADE,
                position INTEGER NOT NULL,
                PRIMARY KEY (playlistId, trackId)
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE lyrics (
                trackId TEXT PRIMARY KEY NOT NULL REFERENCES track(id) ON DELETE CASCADE,
                kind TEXT NOT NULL,
                source TEXT NOT NULL,
                lrc TEXT,
                plain TEXT,
                checkedAt INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE wishlist (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT,
                coverName TEXT,
                addedAt INTEGER NOT NULL
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    private fun changed() {
        version.value = version.value + 1
    }

    private fun Cursor.string(column: String): String? {
        val index = getColumnIndexOrThrow(column)
        return if (isNull(index)) null else getString(index)
    }

    private fun Cursor.int(column: String): Int? {
        val index = getColumnIndexOrThrow(column)
        return if (isNull(index)) null else getInt(index)
    }

    private fun Cursor.long(column: String): Long? {
        val index = getColumnIndexOrThrow(column)
        return if (isNull(index)) null else getLong(index)
    }

    private fun Cursor.toTrack() = TrackRecord(
        id = string("id") ?: "",
        title = string("title") ?: "",
        artist = string("artist") ?: "",
        album = string("album"),
        albumArtist = string("albumArtist"),
        trackNumber = int("trackNumber"),
        discNumber = int("discNumber"),
        year = int("year"),
        genre = string("genre"),
        durationMs = int("durationMs") ?: 0,
        format = string("format") ?: "",
        bitrateKbps = int("bitrateKbps"),
        sampleRate = int("sampleRate"),
        bitDepth = int("bitDepth"),
        fileName = string("fileName") ?: "",
        fileSize = long("fileSize") ?: 0,
        fileHash = string("fileHash"),
        coverName = string("coverName"),
        motionName = string("motionName"),
        motion3x4Name = string("motion3x4Name"),
        isFavorite = (int("isFavorite") ?: 0) != 0,
        playCount = int("playCount") ?: 0,
        lastPlayedAt = long("lastPlayedAt"),
        addedAt = long("addedAt") ?: 0,
        siteId = string("siteId"),
        bpm = int("bpm"),
        palette = string("palette"),
        lyricsKind = string("lyricsKind"),
        lyricsSource = string("lyricsSource"),
    )

    private fun TrackRecord.values() = ContentValues().apply {
        put("id", id)
        put("title", title)
        put("artist", artist)
        put("album", album)
        put("albumArtist", albumArtist)
        put("trackNumber", trackNumber)
        put("discNumber", discNumber)
        put("year", year)
        put("genre", genre)
        put("durationMs", durationMs)
        put("format", format)
        put("bitrateKbps", bitrateKbps)
        put("sampleRate", sampleRate)
        put("bitDepth", bitDepth)
        put("fileName", fileName)
        put("fileSize", fileSize)
        put("fileHash", fileHash)
        put("coverName", coverName)
        put("motionName", motionName)
        put("motion3x4Name", motion3x4Name)
        put("isFavorite", if (isFavorite) 1 else 0)
        put("playCount", playCount)
        put("lastPlayedAt", lastPlayedAt)
        put("addedAt", addedAt)
        put("siteId", siteId)
        put("bpm", bpm)
        put("palette", palette)
        put("lyricsKind", lyricsKind)
        put("lyricsSource", lyricsSource)
    }

    fun allTracks(): List<TrackRecord> = readableDatabase.rawQuery("SELECT * FROM track", null).use { cursor ->
        val list = ArrayList<TrackRecord>(cursor.count)
        while (cursor.moveToNext()) list.add(cursor.toTrack())
        list
    }

    fun track(id: String): TrackRecord? =
        readableDatabase.rawQuery("SELECT * FROM track WHERE id = ?", arrayOf(id)).use { cursor ->
            if (cursor.moveToFirst()) cursor.toTrack() else null
        }

    fun save(track: TrackRecord) {
        val db = writableDatabase
        val values = track.values()
        val updated = db.update("track", values, "id = ?", arrayOf(track.id))
        if (updated == 0) db.insertOrThrow("track", null, values)
        changed()
    }

    fun deleteTrack(id: String) {
        writableDatabase.delete("track", "id = ?", arrayOf(id))
        changed()
    }

    fun setFavorite(id: String, value: Boolean) {
        writableDatabase.execSQL("UPDATE track SET isFavorite = ? WHERE id = ?", arrayOf<Any>(if (value) 1 else 0, id))
        changed()
    }

    fun linkSite(trackId: String, siteId: String) {
        writableDatabase.execSQL("UPDATE track SET siteId = ? WHERE id = ?", arrayOf<Any>(siteId, trackId))
        changed()
    }

    fun markPlayed(id: String, at: Long) {
        writableDatabase.execSQL(
            "UPDATE track SET playCount = playCount + 1, lastPlayedAt = ? WHERE id = ?",
            arrayOf<Any>(at, id),
        )
        changed()
    }

    fun lyrics(trackId: String): LyricsRecord? =
        readableDatabase.rawQuery("SELECT * FROM lyrics WHERE trackId = ?", arrayOf(trackId)).use { cursor ->
            if (!cursor.moveToFirst()) {
                null
            } else {
                LyricsRecord(
                    trackId = cursor.string("trackId") ?: trackId,
                    kind = cursor.string("kind") ?: "none",
                    source = cursor.string("source") ?: "",
                    lrc = cursor.string("lrc"),
                    plain = cursor.string("plain"),
                    checkedAt = cursor.long("checkedAt") ?: 0,
                )
            }
        }

    fun save(lyrics: LyricsRecord) {
        val db = writableDatabase
        val values = ContentValues().apply {
            put("trackId", lyrics.trackId)
            put("kind", lyrics.kind)
            put("source", lyrics.source)
            put("lrc", lyrics.lrc)
            put("plain", lyrics.plain)
            put("checkedAt", lyrics.checkedAt)
        }
        val updated = db.update("lyrics", values, "trackId = ?", arrayOf(lyrics.trackId))
        if (updated == 0) db.insert("lyrics", null, values)
    }

    fun playlists(): List<PlaylistRecord> =
        readableDatabase.rawQuery("SELECT * FROM playlist ORDER BY createdAt DESC", null).use { cursor ->
            val list = ArrayList<PlaylistRecord>()
            while (cursor.moveToNext()) {
                list.add(
                    PlaylistRecord(
                        id = cursor.string("id") ?: "",
                        name = cursor.string("name") ?: "",
                        coverName = cursor.string("coverName"),
                        siteId = cursor.string("siteId"),
                        createdAt = cursor.long("createdAt") ?: 0,
                    ),
                )
            }
            list
        }

    fun trackIds(playlistId: String): List<String> =
        readableDatabase.rawQuery(
            "SELECT trackId FROM playlistTrack WHERE playlistId = ? ORDER BY position",
            arrayOf(playlistId),
        ).use { cursor ->
            val list = ArrayList<String>()
            while (cursor.moveToNext()) list.add(cursor.getString(0))
            list
        }

    fun save(playlist: PlaylistRecord, trackIds: List<String>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val values = ContentValues().apply {
                put("id", playlist.id)
                put("name", playlist.name)
                put("coverName", playlist.coverName)
                put("siteId", playlist.siteId)
                put("createdAt", playlist.createdAt)
            }
            val updated = db.update("playlist", values, "id = ?", arrayOf(playlist.id))
            if (updated == 0) db.insertOrThrow("playlist", null, values)
            db.delete("playlistTrack", "playlistId = ?", arrayOf(playlist.id))
            trackIds.forEachIndexed { index, trackId ->
                db.insertWithOnConflict(
                    "playlistTrack",
                    null,
                    ContentValues().apply {
                        put("playlistId", playlist.id)
                        put("trackId", trackId)
                        put("position", index)
                    },
                    SQLiteDatabase.CONFLICT_IGNORE,
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        changed()
    }

    fun deletePlaylist(id: String) {
        writableDatabase.delete("playlist", "id = ?", arrayOf(id))
        changed()
    }
}
