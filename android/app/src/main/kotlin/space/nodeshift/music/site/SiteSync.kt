package space.nodeshift.music.site

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import space.nodeshift.music.core.DuplicateIndex
import space.nodeshift.music.core.DuplicateKind
import space.nodeshift.music.core.TrackFingerprint
import space.nodeshift.music.data.AppDatabase
import space.nodeshift.music.data.AppPaths
import space.nodeshift.music.data.LibraryStore
import space.nodeshift.music.data.LyricsRecord
import space.nodeshift.music.data.PlaylistRecord
import space.nodeshift.music.data.Prefs
import space.nodeshift.music.data.TrackRecord
import space.nodeshift.music.imports.FileHasher
import space.nodeshift.music.imports.TagIO
import space.nodeshift.music.net.Net
import java.io.File
import java.util.UUID

sealed class SyncPhase {
    data object Idle : SyncPhase()
    data object Loading : SyncPhase()
    data object Downloading : SyncPhase()
    data object Done : SyncPhase()
    data class Failed(val text: String) : SyncPhase()
}

data class ListState(
    val id: String,
    val name: String,
    val total: Int = 0,
    val done: Int = 0,
    val phase: SyncPhase = SyncPhase.Idle,
)

class SiteSync(
    private val database: AppDatabase,
    private val library: LibraryStore,
) {
    var favorites by mutableStateOf(ListState("favorites", "Понравившиеся"))
        private set
    var playlists by mutableStateOf<List<ListState>>(emptyList())
        private set
    var isRefreshing by mutableStateOf(false)
        private set
    var needsLogin by mutableStateOf(false)
        private set
    var lossless by mutableStateOf(Prefs.bool("nsm_lossless", true))
        private set
    var discordPresence by mutableStateOf(Prefs.bool("nsm_discord_presence", true))
        private set

    private var running = false

    fun applyLossless(value: Boolean) {
        lossless = value
        Prefs.putBool("nsm_lossless", value)
    }

    fun applyDiscordPresence(value: Boolean) {
        discordPresence = value
        Prefs.putBool("nsm_discord_presence", value)
    }

    suspend fun refresh() {
        isRefreshing = true
        needsLogin = false
        try {
            val likes = SiteApi.favorites()
            val remote = SiteApi.playlists()
            val known = library.tracks.mapNotNull { it.siteId }.toSet()
            val here = likes.count { known.contains(it.id.value) }
            favorites = favorites.copy(
                total = likes.size,
                done = here,
                phase = if (here >= likes.size && likes.isNotEmpty()) SyncPhase.Done else SyncPhase.Idle,
            )
            playlists = remote.map { ListState(it.id.value, it.name, it.trackCount ?: 0) }
        } catch (error: SiteException) {
            if (error.kind == SiteException.Kind.Unauthorized || error.kind == SiteException.Kind.NoToken) {
                needsLogin = true
            } else {
                favorites = favorites.copy(phase = SyncPhase.Failed("Не получилось загрузить список"))
            }
        } catch (_: Exception) {
            favorites = favorites.copy(phase = SyncPhase.Failed("Не получилось загрузить список"))
        } finally {
            isRefreshing = false
        }
    }

    suspend fun downloadFavorites() {
        if (running) return
        running = true
        try {
            favorites = favorites.copy(phase = SyncPhase.Loading)
            val remote = SiteApi.favorites()
            favorites = favorites.copy(total = remote.size, done = 0, phase = SyncPhase.Downloading)
            val ids = ingest(remote) { done -> favorites = favorites.copy(done = done) }
            withContext(Dispatchers.IO) { ids.forEach { runCatching { database.setFavorite(it, true) } } }
            favorites = favorites.copy(phase = SyncPhase.Done)
        } catch (_: Exception) {
            favorites = favorites.copy(phase = SyncPhase.Failed("Не получилось скачать"))
        } finally {
            running = false
        }
    }

    private fun updatePlaylist(id: String, change: (ListState) -> ListState) {
        playlists = playlists.map { if (it.id == id) change(it) else it }
    }

    suspend fun downloadPlaylist(id: String) {
        if (running || playlists.none { it.id == id }) return
        running = true
        try {
            updatePlaylist(id) { it.copy(phase = SyncPhase.Loading) }
            val detail = SiteApi.playlist(id)
            val remote = detail.tracks.sortedBy { it.position }.map { it.track }
            updatePlaylist(id) { it.copy(total = remote.size, done = 0, phase = SyncPhase.Downloading) }
            val ids = ingest(remote) { done -> updatePlaylist(id) { it.copy(done = done) } }
            val coverName = detail.coverFilename?.let { fetchCover(it) }
            withContext(Dispatchers.IO) {
                database.save(
                    PlaylistRecord("site-$id", detail.name, coverName, id, System.currentTimeMillis()),
                    ids,
                )
            }
            updatePlaylist(id) { it.copy(phase = SyncPhase.Done) }
        } catch (_: Exception) {
            updatePlaylist(id) { it.copy(phase = SyncPhase.Failed("Не получилось скачать")) }
        } finally {
            running = false
        }
    }

    private fun fingerprint(track: SiteTrack) = TrackFingerprint(
        id = "site-${track.id.value}",
        artist = track.artist,
        title = track.title,
        durationMs = track.durationSeconds?.let { (it * 1000).toInt() },
        fileHash = null,
        format = track.format ?: "",
    )

    private suspend fun ingest(remote: List<SiteTrack>, progress: (Int) -> Unit): List<String> {
        val current = library.tracks
        val bySite = HashMap<String, String>()
        current.forEach { track -> track.siteId?.let { bySite[it] = track.id } }
        val index = DuplicateIndex(
            current.map {
                TrackFingerprint(it.id, it.artist, it.title, it.durationMs, it.fileHash, it.format, it.bitrateKbps)
            },
        )
        val ids = ArrayList<String>()
        var done = 0
        for (item in remote) {
            val existing = bySite[item.id.value]
            if (existing != null) {
                ids.add(existing)
            } else {
                val match = index.matches(fingerprint(item)).firstOrNull { it.kind == DuplicateKind.SAME_TRACK }
                if (match != null) {
                    withContext(Dispatchers.IO) { database.linkSite(match.existingId, item.id.value) }
                    bySite[item.id.value] = match.existingId
                    ids.add(match.existingId)
                } else {
                    val saved = runCatching { download(item) }.getOrNull()
                    if (saved != null) {
                        bySite[item.id.value] = saved.id
                        index.add(TrackFingerprint(saved.id, saved.artist, saved.title, saved.durationMs, saved.fileHash, saved.format))
                        ids.add(saved.id)
                    }
                }
            }
            done += 1
            progress(done)
        }
        return ids
    }

    private suspend fun fetchCover(name: String): String? {
        val local = "site-$name"
        val target = AppPaths.coverFile(local)
        if (target.exists()) return local
        return if (runCatching { Net.download(SiteApi.coverUrl(name), target) }.isSuccess) local else null
    }

    private suspend fun fetchMotion(name: String): String? {
        val local = "site-$name"
        val target = AppPaths.motionFile(local)
        if (target.exists()) return local
        return if (runCatching { Net.download(SiteApi.motionUrl(name), target) }.isSuccess) local else null
    }

    private suspend fun download(remote: SiteTrack): TrackRecord {
        val url = SiteApi.audioUrl(remote, lossless)
        val source = if (!lossless && remote.streamFilename != null) remote.streamFilename else remote.filename
        val ext = source.substringAfterLast('.', "mp3").lowercase()
        val id = UUID.randomUUID().toString()
        val fileName = "$id.$ext"
        val destination = AppPaths.trackFile(fileName)
        Net.download(url, destination)
        val hash = withContext(Dispatchers.IO) { FileHasher.hash(destination) }
        val coverName = remote.coverFilename?.let { fetchCover(it) }
        val motionName = remote.motionFilename?.let { fetchMotion(it) }
        val tags = withContext(Dispatchers.IO) { TagIO.read(destination) }
        val seconds = remote.durationSeconds ?: tags?.duration ?: 0.0
        val track = TrackRecord(
            id = id,
            title = remote.title,
            artist = remote.artist,
            album = remote.album,
            trackNumber = tags?.trackNumber,
            discNumber = tags?.discNumber,
            year = tags?.year,
            genre = tags?.genre,
            durationMs = Math.round(seconds * 1000).toInt(),
            format = (remote.format ?: ext).lowercase(),
            bitrateKbps = tags?.bitrateKbps,
            sampleRate = tags?.sampleRate,
            fileName = fileName,
            fileSize = destination.length(),
            fileHash = hash,
            coverName = coverName,
            motionName = motionName,
            siteId = remote.id.value,
        )
        withContext(Dispatchers.IO) { database.save(track) }
        val lyrics = SiteApi.lyrics(remote.id.value)
        if (lyrics != null) {
            val synced = lyrics.synced
            val plain = lyrics.plain
            withContext(Dispatchers.IO) {
                if (!synced.isNullOrEmpty()) {
                    database.save(LyricsRecord(id, "line", lyrics.source ?: "site", synced, plain))
                } else if (!plain.isNullOrEmpty()) {
                    database.save(LyricsRecord(id, "plain", lyrics.source ?: "site", null, plain))
                }
            }
        }
        return track
    }
}
