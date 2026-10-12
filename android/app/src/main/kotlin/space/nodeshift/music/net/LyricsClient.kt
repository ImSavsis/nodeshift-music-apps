package space.nodeshift.music.net

import kotlinx.serialization.Serializable
import space.nodeshift.music.core.LyricsCandidate
import space.nodeshift.music.core.LyricsKind
import space.nodeshift.music.core.LyricsQuery
import space.nodeshift.music.core.LyricsVerifier

@Serializable
private data class LrclibItem(
    val trackName: String? = null,
    val artistName: String? = null,
    val albumName: String? = null,
    val duration: Double? = null,
    val instrumental: Boolean? = null,
    val plainLyrics: String? = null,
    val syncedLyrics: String? = null,
)

data class FoundLyrics(val kind: LyricsKind, val lrc: String?, val plain: String?, val source: String)

object LyricsClient {
    private const val BASE = "https://lrclib.net/api"

    suspend fun fetch(title: String, artist: String, album: String?, duration: Double?): FoundLyrics? {
        val query = LyricsQuery(title, artist, duration)
        val candidates = mutableListOf<LyricsCandidate>()
        get(title, artist, album, duration)?.let { candidates.add(it) }
        if (LyricsVerifier.best(candidates, query) == null) {
            candidates.addAll(search(mapOf("track_name" to title, "artist_name" to artist)))
            if (LyricsVerifier.best(candidates, query) == null) {
                candidates.addAll(search(mapOf("q" to "$artist $title")))
            }
        }
        val winner = LyricsVerifier.best(candidates, query) ?: return null
        val candidate = winner.first
        if (winner.second == LyricsKind.PLAIN) {
            return FoundLyrics(LyricsKind.PLAIN, null, candidate.plain, "lrclib-verified")
        }
        return FoundLyrics(winner.second, candidate.synced, candidate.plain, "lrclib-verified")
    }

    private fun candidate(item: LrclibItem): LyricsCandidate? {
        val name = item.trackName ?: return null
        val artist = item.artistName ?: return null
        return LyricsCandidate(name, artist, item.duration, item.syncedLyrics, item.plainLyrics, item.instrumental ?: false)
    }

    private suspend fun get(title: String, artist: String, album: String?, duration: Double?): LyricsCandidate? {
        val items = mutableMapOf("track_name" to title, "artist_name" to artist)
        if (!album.isNullOrEmpty()) items["album_name"] = album
        if (duration != null) items["duration"] = Math.round(duration).toString()
        val url = Net.components("$BASE/get", items) ?: return null
        RateLimiter.wait("lrclib", 350)
        val item = runCatching { Net.json.decodeFromString<LrclibItem>(Net.text(url)) }.getOrNull() ?: return null
        return candidate(item)
    }

    private suspend fun search(items: Map<String, String>): List<LyricsCandidate> {
        val url = Net.components("$BASE/search", items) ?: return emptyList()
        RateLimiter.wait("lrclib", 350)
        val list = runCatching { Net.json.decodeFromString<List<LrclibItem>>(Net.text(url)) }.getOrNull() ?: return emptyList()
        return list.mapNotNull(::candidate)
    }
}
