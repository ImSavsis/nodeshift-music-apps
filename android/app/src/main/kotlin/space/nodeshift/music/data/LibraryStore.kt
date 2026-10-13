package space.nodeshift.music.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.Normalizer

enum class LibrarySort(val label: String) {
    Newest("Новые"),
    Popular("Популярные"),
    Title("По названию"),
}

enum class FormatFilter(val label: String) {
    All("Все"),
    Flac("FLAC"),
    Mp3("MP3"),
}

enum class LibraryViewMode { Grid, List }

private val marks = Regex("\\p{M}+")

private fun fold(text: String): String =
    Normalizer.normalize(text, Normalizer.Form.NFD).replace(marks, "").lowercase()

class LibraryStore(private val database: AppDatabase, private val scope: CoroutineScope) {
    var tracks by mutableStateOf<List<TrackRecord>>(emptyList())
        private set
    var playlists by mutableStateOf<List<PlaylistRecord>>(emptyList())
        private set
    var loaded by mutableStateOf(false)
        private set
    var query by mutableStateOf("")
    var sort by mutableStateOf(LibrarySort.Newest)
    var formatFilter by mutableStateOf(FormatFilter.All)
    var viewMode by mutableStateOf(
        if (Prefs.string("nsm_view") == "list") LibraryViewMode.List else LibraryViewMode.Grid,
    )
        private set
    var menuTrack by mutableStateOf<TrackRecord?>(null)

    init {
        scope.launch {
            database.changes.collect {
                val list = withContext(Dispatchers.IO) { database.allTracks() }
                val lists = withContext(Dispatchers.IO) { database.playlists() }
                tracks = list
                playlists = lists
                loaded = true
            }
        }
    }

    fun changeViewMode(mode: LibraryViewMode) {
        viewMode = mode
        Prefs.putString("nsm_view", if (mode == LibraryViewMode.List) "list" else "grid")
    }

    val filtered: List<TrackRecord>
        get() {
            var list = tracks
            when (formatFilter) {
                FormatFilter.All -> Unit
                FormatFilter.Flac -> list = list.filter { it.format.lowercase() == "flac" }
                FormatFilter.Mp3 -> list = list.filter { it.format.lowercase() == "mp3" }
            }
            val needle = fold(query.trim())
            if (needle.isNotEmpty()) {
                list = list.filter {
                    fold(it.title).contains(needle) || fold(it.artist).contains(needle) || fold(it.album ?: "").contains(needle)
                }
            }
            return when (sort) {
                LibrarySort.Newest -> list.sortedByDescending { it.addedAt }
                LibrarySort.Popular -> list.sortedByDescending { it.playCount }
                LibrarySort.Title -> list.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title })
            }
        }

    val recent: List<TrackRecord>
        get() = tracks.filter { it.lastPlayedAt != null }.sortedByDescending { it.lastPlayedAt }.take(12)

    val favorites: List<TrackRecord>
        get() = tracks.filter { it.isFavorite }.sortedByDescending { it.addedAt }

    fun track(id: String): TrackRecord? = tracks.firstOrNull { it.id == id }

    suspend fun playlistTracks(playlist: PlaylistRecord): List<TrackRecord> {
        val ids = withContext(Dispatchers.IO) { database.trackIds(playlist.id) }
        val byId = tracks.associateBy { it.id }
        return ids.mapNotNull { byId[it] }
    }

    fun toggleFavorite(id: String) {
        val current = track(id) ?: return
        scope.launch(Dispatchers.IO) { database.setFavorite(id, !current.isFavorite) }
    }

    fun markPlayed(id: String) {
        scope.launch(Dispatchers.IO) { database.markPlayed(id, System.currentTimeMillis()) }
    }

    fun save(track: TrackRecord) {
        scope.launch(Dispatchers.IO) { database.save(track) }
    }

    fun delete(track: TrackRecord) {
        val others = tracks.filter { it.id != track.id }
        scope.launch(Dispatchers.IO) {
            runCatching { track.file.delete() }
            track.coverName?.let { cover ->
                if (others.none { it.coverName == cover }) runCatching { AppPaths.coverFile(cover).delete() }
            }
            track.motionName?.let { motion ->
                if (others.none { it.motionName == motion }) runCatching { AppPaths.motionFile(motion).delete() }
            }
            database.deleteTrack(track.id)
        }
    }

    fun deletePlaylist(playlist: PlaylistRecord) {
        scope.launch(Dispatchers.IO) { database.deletePlaylist(playlist.id) }
    }
}
