package space.nodeshift.music.data

import java.io.File

data class TrackRecord(
    val id: String,
    val title: String,
    val artist: String,
    val album: String? = null,
    val albumArtist: String? = null,
    val trackNumber: Int? = null,
    val discNumber: Int? = null,
    val year: Int? = null,
    val genre: String? = null,
    val durationMs: Int = 0,
    val format: String = "",
    val bitrateKbps: Int? = null,
    val sampleRate: Int? = null,
    val bitDepth: Int? = null,
    val fileName: String = "",
    val fileSize: Long = 0,
    val fileHash: String? = null,
    val coverName: String? = null,
    val motionName: String? = null,
    val motion3x4Name: String? = null,
    val isFavorite: Boolean = false,
    val playCount: Int = 0,
    val lastPlayedAt: Long? = null,
    val addedAt: Long = System.currentTimeMillis(),
    val siteId: String? = null,
    val bpm: Int? = null,
    val palette: String? = null,
    val lyricsKind: String? = null,
    val lyricsSource: String? = null,
) {
    val durationSeconds: Double
        get() = durationMs / 1000.0

    val file: File
        get() = AppPaths.trackFile(fileName)
}

data class PlaylistRecord(
    val id: String,
    val name: String,
    val coverName: String? = null,
    val siteId: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
)

data class LyricsRecord(
    val trackId: String,
    val kind: String,
    val source: String,
    val lrc: String? = null,
    val plain: String? = null,
    val checkedAt: Long = System.currentTimeMillis(),
)

data class WishlistRecord(
    val id: String,
    val title: String,
    val artist: String,
    val album: String? = null,
    val coverName: String? = null,
    val addedAt: Long = System.currentTimeMillis(),
)
