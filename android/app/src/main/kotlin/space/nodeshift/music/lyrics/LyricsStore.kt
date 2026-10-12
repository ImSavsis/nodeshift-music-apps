package space.nodeshift.music.lyrics

import androidx.compose.runtime.mutableStateMapOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import space.nodeshift.music.core.LrcParser
import space.nodeshift.music.core.LyricLine
import space.nodeshift.music.core.LyricsKind
import space.nodeshift.music.data.AppDatabase
import space.nodeshift.music.data.LyricsRecord
import space.nodeshift.music.data.TrackRecord
import space.nodeshift.music.imports.TagIO
import space.nodeshift.music.net.LyricsClient

sealed class LyricsState {
    data object Loading : LyricsState()
    data class Synced(val lines: List<LyricLine>, val source: String?) : LyricsState()
    data class Plain(val text: String, val source: String?) : LyricsState()
    data object None : LyricsState()
}

class LyricsStore(private val database: AppDatabase) {
    private val states = mutableStateMapOf<String, LyricsState>()
    private val inFlight = HashSet<String>()

    fun state(track: TrackRecord): LyricsState = states[track.id] ?: LyricsState.Loading

    suspend fun ensure(track: TrackRecord) {
        if (states.containsKey(track.id) || inFlight.contains(track.id)) return
        inFlight.add(track.id)
        try {
            val stored = withContext(Dispatchers.IO) { stored(track) }
            if (stored != null) {
                states[track.id] = stored
                return
            }
            resolve(track, force = false)
        } finally {
            inFlight.remove(track.id)
        }
    }

    suspend fun refresh(track: TrackRecord) {
        states[track.id] = LyricsState.Loading
        inFlight.add(track.id)
        try {
            resolve(track, force = true)
        } finally {
            inFlight.remove(track.id)
        }
    }

    private fun stored(track: TrackRecord): LyricsState? {
        val record = database.lyrics(track.id) ?: return null
        return when (record.kind) {
            "word", "line" -> {
                val lrc = record.lrc ?: return null
                val lines = LrcParser.parse(lrc)
                if (lines.isEmpty()) null else LyricsState.Synced(lines, record.source)
            }
            "plain" -> {
                val plain = record.plain
                if (plain.isNullOrEmpty()) null else LyricsState.Plain(plain, record.source)
            }
            else -> if (System.currentTimeMillis() - record.checkedAt < 12 * 3600 * 1000L) LyricsState.None else null
        }
    }

    private suspend fun save(track: TrackRecord, kind: String, source: String, lrc: String?, plain: String?) {
        withContext(Dispatchers.IO) {
            runCatching { database.save(LyricsRecord(track.id, kind, source, lrc, plain, System.currentTimeMillis())) }
        }
    }

    private suspend fun resolve(track: TrackRecord, force: Boolean) {
        if (!force) {
            val embedded = withContext(Dispatchers.IO) { TagIO.read(track.file)?.lyrics }
            if (!embedded.isNullOrEmpty()) {
                val lines = LrcParser.parse(embedded)
                if (lines.size >= 2) {
                    val kind = if (LrcParser.kind(lines) == LyricsKind.WORD_SYNCED) "word" else "line"
                    save(track, kind, "embedded", embedded, null)
                    states[track.id] = LyricsState.Synced(lines, "embedded")
                } else {
                    save(track, "plain", "embedded", null, embedded)
                    states[track.id] = LyricsState.Plain(embedded, "embedded")
                }
                return
            }
        }
        val duration = if (track.durationMs > 0) track.durationSeconds else null
        val found = LyricsClient.fetch(track.title, track.artist, track.album, duration)
        if (found == null) {
            save(track, "none", "none", null, null)
            states[track.id] = LyricsState.None
            return
        }
        when (found.kind) {
            LyricsKind.WORD_SYNCED, LyricsKind.LINE_SYNCED -> {
                val lines = found.lrc?.let { LrcParser.parse(it) } ?: emptyList()
                val plain = found.plain
                if (lines.isEmpty() && plain != null) {
                    save(track, "plain", found.source, null, plain)
                    states[track.id] = LyricsState.Plain(plain, found.source)
                } else {
                    save(track, if (found.kind == LyricsKind.WORD_SYNCED) "word" else "line", found.source, found.lrc, found.plain)
                    states[track.id] = LyricsState.Synced(lines, found.source)
                }
            }
            LyricsKind.PLAIN -> {
                val plain = found.plain ?: ""
                save(track, "plain", found.source, null, plain)
                states[track.id] = LyricsState.Plain(plain, found.source)
            }
            LyricsKind.NONE -> {
                save(track, "none", "none", null, null)
                states[track.id] = LyricsState.None
            }
        }
    }
}
