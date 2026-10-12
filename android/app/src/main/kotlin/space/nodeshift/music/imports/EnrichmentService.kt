package space.nodeshift.music.imports

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import space.nodeshift.music.core.TextMatching
import space.nodeshift.music.data.AppDatabase
import space.nodeshift.music.data.AppPaths
import space.nodeshift.music.data.Prefs
import space.nodeshift.music.data.TrackRecord
import space.nodeshift.music.lyrics.LyricsStore
import space.nodeshift.music.net.MotionCoverFinder
import java.security.MessageDigest

class EnrichmentService(
    private val database: AppDatabase,
    private val lyrics: LyricsStore,
    private val scope: CoroutineScope,
) {
    private val queue = ArrayDeque<TrackRecord>()
    private var running = false
    private val albumsDone = HashSet<String>()

    fun enqueue(track: TrackRecord) {
        queue.addLast(track)
        if (!running) {
            running = true
            scope.launch { drain() }
        }
    }

    private suspend fun drain() {
        try {
            while (queue.isNotEmpty()) {
                val track = queue.removeFirst()
                runCatching { lyrics.ensure(track) }
                runCatching { findMotion(track) }
            }
        } finally {
            running = false
        }
    }

    private fun checkedRecently(key: String): Boolean {
        val stamp = Prefs.doubleMap("nsm_motion_checked")[key] ?: return false
        return System.currentTimeMillis() / 1000.0 - stamp < 30 * 86_400
    }

    private fun markChecked(key: String) {
        val checks = Prefs.doubleMap("nsm_motion_checked").toMutableMap()
        checks[key] = System.currentTimeMillis() / 1000.0
        Prefs.putDoubleMap("nsm_motion_checked", checks)
    }

    private suspend fun findMotion(track: TrackRecord) {
        if (!motionEnabled) return
        val key = albumKey(track) ?: return
        val album = track.album ?: return
        if (albumsDone.contains(key) || checkedRecently(key) || track.motionName != null) return
        albumsDone.add(key)
        val artist = track.albumArtist ?: track.artist
        val files = MotionCoverFinder.find(artist, album, AppPaths.motionDir, fileKey(key))
        markChecked(key)
        if (files == null) return
        withContext(Dispatchers.IO) {
            val siblings = database.allTracks().filter { albumKey(it) == key }
            for (sibling in siblings) {
                database.save(sibling.copy(motionName = files.square?.name, motion3x4Name = files.tall?.name))
            }
        }
    }

    companion object {
        val motionEnabled: Boolean
            get() = Prefs.bool("nsm_motion_auto", true)

        fun albumKey(track: TrackRecord): String? {
            val album = track.album
            if (album.isNullOrEmpty()) return null
            val artist = track.albumArtist ?: track.artist
            return TextMatching.artistKey(artist) + "|" + TextMatching.normalize(album)
        }

        private fun fileKey(albumKey: String): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(albumKey.toByteArray(Charsets.UTF_8))
            return digest.take(8).joinToString("") { "%02x".format(it.toInt() and 0xFF) }
        }
    }
}
