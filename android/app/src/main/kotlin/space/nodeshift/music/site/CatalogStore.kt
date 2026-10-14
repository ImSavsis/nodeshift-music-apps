package space.nodeshift.music.site

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import space.nodeshift.music.data.FormatFilter
import space.nodeshift.music.data.LibraryStore
import space.nodeshift.music.data.LibrarySort
import space.nodeshift.music.data.TrackRecord
import space.nodeshift.music.design.CoverSource
import space.nodeshift.music.ui.ToastCenter
import kotlin.coroutines.cancellation.CancellationException

fun SiteTrack.catalogRecord(): TrackRecord = TrackRecord(
    id = "site:${id.value}",
    title = title,
    artist = artist,
    album = album,
    durationMs = ((durationSeconds ?: 0.0) * 1000).toInt(),
    format = (format ?: "mp3").lowercase(),
    coverName = coverFilename?.let { CoverSource.remoteName(it) },
    motionName = motionFilename?.let { CoverSource.remoteName(it) },
    playCount = playCount ?: 0,
    siteId = id.value,
    streamUrl = SiteApi.audioUrl(this, false),
)

class CatalogStore(
    private val library: LibraryStore,
    private val site: SiteSession,
    private val toasts: ToastCenter,
    private val scope: CoroutineScope,
) {
    var tracks by mutableStateOf<List<TrackRecord>>(emptyList())
        private set
    var query by mutableStateOf("")
        private set
    var sort by mutableStateOf(LibrarySort.Newest)
        private set
    var formatFilter by mutableStateOf(FormatFilter.All)
        private set
    var isLoading by mutableStateOf(false)
        private set
    var hasMore by mutableStateOf(true)
        private set
    var failed by mutableStateOf(false)
        private set
    var likedIds by mutableStateOf<Set<String>>(emptySet())
        private set

    private var offset = 0
    private var generation = 0
    private var searchJob: Job? = null

    private val apiSort: String
        get() = when (sort) {
            LibrarySort.Newest -> "new"
            LibrarySort.Popular -> "popular"
            LibrarySort.Title -> "title"
        }

    fun startIfNeeded() {
        if (tracks.isEmpty() && !isLoading) reload()
    }

    fun changeQuery(value: String) {
        query = value
        searchJob?.cancel()
        searchJob = scope.launch {
            delay(350)
            reload()
        }
    }

    fun changeSort(value: LibrarySort) {
        sort = value
        reload()
    }

    fun changeFormat(value: FormatFilter) {
        formatFilter = value
        reload()
    }

    fun reload() {
        generation += 1
        offset = 0
        hasMore = true
        load(true)
    }

    fun loadMore() {
        if (!hasMore || isLoading) return
        load(false)
    }

    fun record(item: SiteTrack): TrackRecord =
        library.tracks.firstOrNull { it.siteId == item.id.value } ?: item.catalogRecord()

    private fun load(reset: Boolean) {
        val token = generation
        val needle = query.trim()
        val sortKey = apiSort
        val format = if (formatFilter == FormatFilter.All) null else formatFilter.name.lowercase()
        val start = offset
        isLoading = true
        failed = false
        scope.launch {
            try {
                val page = SiteApi.catalog(needle, sortKey, format, PAGE_SIZE, start)
                if (token != generation) return@launch
                val mapped = page.filter { it.mediaKind != "video" }.map { record(it) }
                tracks = if (reset) {
                    mapped
                } else {
                    val known = tracks.mapTo(HashSet()) { it.id }
                    tracks + mapped.filter { it.id !in known }
                }
                offset = start + page.size
                hasMore = page.size == PAGE_SIZE
                isLoading = false
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                if (token != generation) return@launch
                failed = true
                hasMore = false
                isLoading = false
            }
        }
    }

    suspend fun wave(): List<TrackRecord> = try {
        SiteApi.wave(40).map { record(it) }
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        toasts.show("Не получилось запустить волну")
        emptyList()
    }

    suspend fun refreshLikes() {
        if (!site.isLoggedIn) {
            likedIds = emptySet()
            return
        }
        try {
            likedIds = SiteApi.likedIds()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            return
        }
    }

    fun isFavorite(track: TrackRecord): Boolean {
        val siteId = track.siteId
        return if (track.isRemote && siteId != null) siteId in likedIds else track.isFavorite
    }

    fun toggleFavorite(track: TrackRecord) {
        val siteId = track.siteId
        if (!track.isRemote || siteId == null) {
            library.toggleFavorite(track.id)
            return
        }
        if (!site.isLoggedIn) {
            toasts.show("Войди через сайт, чтобы ставить лайки")
            return
        }
        val value = siteId !in likedIds
        likedIds = if (value) likedIds + siteId else likedIds - siteId
        scope.launch {
            try {
                SiteApi.setLiked(siteId, value)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                likedIds = if (value) likedIds - siteId else likedIds + siteId
                toasts.show("Не получилось сохранить лайк")
            }
        }
    }

    companion object {
        const val PAGE_SIZE = 30
    }
}
