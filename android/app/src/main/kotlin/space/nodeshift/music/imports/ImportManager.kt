package space.nodeshift.music.imports

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import space.nodeshift.music.core.DuplicateIndex
import space.nodeshift.music.core.DuplicateKind
import space.nodeshift.music.core.FilenameParser
import space.nodeshift.music.core.ParsedName
import space.nodeshift.music.core.TextMatching
import space.nodeshift.music.core.TrackFingerprint
import space.nodeshift.music.data.AppDatabase
import space.nodeshift.music.data.AppPaths
import space.nodeshift.music.data.TrackRecord
import space.nodeshift.music.net.CatalogClient
import space.nodeshift.music.net.CatalogMatch
import space.nodeshift.music.net.CatalogQuery
import space.nodeshift.music.net.Net
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

sealed class ImportState {
    data object Waiting : ImportState()
    data class Working(val text: String) : ImportState()
    data object Done : ImportState()
    data class Duplicate(val existingId: String, val kind: DuplicateKind, val betterQuality: Boolean) : ImportState()
    data class Skipped(val text: String) : ImportState()
    data class Failed(val text: String) : ImportState()
}

data class ImportItem(
    val id: String,
    val name: String,
    val state: ImportState = ImportState.Waiting,
    val title: String? = null,
    val artist: String? = null,
    val coverName: String? = null,
    val trackId: String? = null,
)

enum class DuplicateDecision { Skip, KeepBoth, Replace }

data class ImportSummary(val added: Int = 0, val duplicates: Int = 0, val failed: Int = 0, val ignored: Int = 0)

interface CatalogProviding {
    suspend fun lookup(query: CatalogQuery): CatalogMatch?

    suspend fun downloadCover(url: String): ByteArray?
}

object NetworkCatalog : CatalogProviding {
    override suspend fun lookup(query: CatalogQuery): CatalogMatch? = CatalogClient.lookup(query)

    override suspend fun downloadCover(url: String): ByteArray? = runCatching { Net.bytes(url) }.getOrNull()
}

private class PendingDuplicate(
    val track: TrackRecord,
    val replacing: String,
)

class ImportManager(
    private val context: Context,
    private val database: AppDatabase,
    private val scope: CoroutineScope,
    private val catalog: CatalogProviding? = NetworkCatalog,
) {
    val items = mutableStateListOf<ImportItem>()
    var isRunning by mutableStateOf(false)
        private set
    var summary by mutableStateOf(ImportSummary())
        private set

    var onTrackAdded: ((TrackRecord) -> Unit)? = null
    var onTrackRemoved: ((String) -> Unit)? = null

    private var index = DuplicateIndex()
    private val pending = HashMap<String, PendingDuplicate>()
    private val albumCovers = HashMap<String, String>()
    private val queue = ArrayDeque<List<ImportSource>>()
    private var worker: Job? = null

    val pendingDuplicates: Int
        get() = pending.size

    fun add(sources: List<ImportSource>) {
        if (sources.isEmpty()) return
        queue.addLast(sources)
        if (worker?.isActive != true) {
            worker = scope.launch {
                while (queue.isNotEmpty()) run(queue.removeFirst())
            }
        }
    }

    fun clearFinished() {
        items.removeAll { it.state is ImportState.Done || it.state is ImportState.Skipped || it.state is ImportState.Failed }
        if (items.isEmpty()) summary = ImportSummary()
    }

    fun decide(id: String, decision: DuplicateDecision) {
        val position = items.indexOfFirst { it.id == id }
        val waiting = pending.remove(id)
        if (position < 0 || waiting == null) return
        when (decision) {
            DuplicateDecision.Skip -> {
                discard(waiting.track)
                items[position] = items[position].copy(state = ImportState.Skipped("Пропущен: уже есть"))
                summary = summary.copy(duplicates = summary.duplicates + 1)
            }
            DuplicateDecision.KeepBoth -> commit(waiting, position, null)
            DuplicateDecision.Replace -> commit(waiting, position, waiting.replacing)
        }
    }

    fun skipAllDuplicates() {
        for (id in pending.keys.toList()) decide(id, DuplicateDecision.Skip)
    }

    private suspend fun run(sources: List<ImportSource>) {
        isRunning = true
        val scratch = File(AppPaths.scratchDir, UUID.randomUUID().toString())
        try {
            val scan = withContext(Dispatchers.IO) { ImportScanner.scan(context, sources, scratch) }
            summary = summary.copy(ignored = summary.ignored + scan.skipped)
            loadIndex()
            val parsedByCandidate = HashMap<ImportCandidate, ParsedName>()
            for ((_, group) in scan.candidates.groupBy { it.group }) {
                val parsed = FilenameParser.parseBatch(group.map { it.name })
                group.zip(parsed).forEach { (candidate, result) -> parsedByCandidate[candidate] = result }
            }
            val ids = HashMap<ImportCandidate, String>()
            for (candidate in scan.candidates) {
                val id = UUID.randomUUID().toString()
                ids[candidate] = id
                val parsed = parsedByCandidate[candidate]
                items.add(ImportItem(id = id, name = candidate.name, title = parsed?.title, artist = parsed?.artist))
            }
            for (candidate in scan.candidates) {
                val id = ids[candidate] ?: continue
                process(candidate, id, parsedByCandidate[candidate] ?: ParsedName())
            }
        } finally {
            withContext(Dispatchers.IO) { scratch.deleteRecursively() }
            isRunning = false
        }
    }

    private suspend fun loadIndex() {
        val tracks = withContext(Dispatchers.IO) { database.allTracks() }
        index = DuplicateIndex(tracks.map(::fingerprint))
    }

    private fun fingerprint(track: TrackRecord) = TrackFingerprint(
        id = track.id,
        artist = track.artist,
        title = track.title,
        durationMs = track.durationMs,
        fileHash = track.fileHash,
        format = track.format,
        bitrateKbps = track.bitrateKbps,
    )

    private fun update(id: String, change: (ImportItem) -> ImportItem) {
        val position = items.indexOfFirst { it.id == id }
        if (position >= 0) items[position] = change(items[position])
    }

    private fun discard(track: TrackRecord) {
        runCatching { AppPaths.trackFile(track.fileName).delete() }
        val cover = track.coverName
        if (cover != null && !albumCovers.values.contains(cover)) runCatching { AppPaths.coverFile(cover).delete() }
    }

    private suspend fun process(candidate: ImportCandidate, id: String, parsed: ParsedName) {
        val ext = candidate.extension
        val trackId = UUID.randomUUID().toString()
        val fileName = "$trackId.$ext"
        val destination = AppPaths.trackFile(fileName)
        update(id) { it.copy(state = ImportState.Working("Копируем")) }

        val copied = try {
            withContext(Dispatchers.IO) { FileHasher.copyAndHash(candidate.open(context.contentResolver), destination) }
        } catch (_: Exception) {
            destination.delete()
            update(id) { it.copy(state = ImportState.Failed("Не удалось скопировать")) }
            summary = summary.copy(failed = summary.failed + 1)
            return
        }

        if (index.existingId(copied.first) != null) {
            destination.delete()
            update(id) { it.copy(state = ImportState.Skipped("Уже есть в библиотеке")) }
            summary = summary.copy(duplicates = summary.duplicates + 1)
            return
        }

        update(id) { it.copy(state = ImportState.Working("Читаем теги")) }
        val tags = withContext(Dispatchers.IO) { TagIO.read(destination) }
        if (tags == null) {
            destination.delete()
            update(id) { it.copy(state = ImportState.Failed("Формат не читается")) }
            summary = summary.copy(failed = summary.failed + 1)
            return
        }

        val stem = candidate.name.substringBeforeLast('.')
        var title = tags.title ?: parsed.title ?: stem
        var artist = tags.artist ?: parsed.artist ?: ""
        var album = tags.album
        var albumArtist = tags.albumArtist
        var trackNumber = tags.trackNumber ?: parsed.track
        var discNumber = tags.discNumber ?: parsed.disc
        var year = tags.year
        var genre = tags.genre
        var isrc: String? = null
        var coverData = tags.cover
        val duration = tags.duration ?: 0.0

        if (catalog != null) {
            update(id) { it.copy(state = ImportState.Working("Ищем в каталоге")) }
            val query = CatalogQuery(title, artist, album, if (duration > 0) duration else null)
            val match = catalog.lookup(query)
            if (match != null) {
                if (tags.title == null || TextMatching.titleRatio(title, match.title) >= 0.95) title = match.title
                if (tags.artist == null || artist.isEmpty() || TextMatching.artistRatio(artist, match.artist) >= 0.95) artist = match.artist
                album = album ?: match.album
                albumArtist = albumArtist ?: match.albumArtist
                trackNumber = trackNumber ?: match.trackNumber
                discNumber = discNumber ?: match.discNumber
                year = year ?: match.year
                genre = genre ?: match.genre
                isrc = match.isrc
                val coverUrl = match.coverUrl
                if (coverData == null && coverUrl != null) coverData = catalog.downloadCover(coverUrl)
            }
        }

        if (artist.isEmpty()) artist = "Неизвестный исполнитель"

        val albumKey = album?.let { artist.lowercase() + "|" + it.lowercase() }
        var coverName: String? = null
        var jpeg: ByteArray? = null
        val known = albumKey?.let { albumCovers[it] }
        if (known != null) {
            coverName = known
        } else if (coverData != null) {
            val source = coverData
            jpeg = withContext(Dispatchers.Default) { normalizedJpeg(source) }
            if (jpeg != null) coverName = "${UUID.randomUUID()}.jpg"
        }

        update(id) { it.copy(state = ImportState.Working("Пишем теги")) }
        val writeTags = WriteTags(
            title = title,
            artist = artist,
            album = album,
            albumArtist = albumArtist,
            genre = genre,
            trackNumber = trackNumber,
            discNumber = discNumber,
            year = year,
            isrc = isrc,
            cover = jpeg,
        )
        withContext(Dispatchers.IO) { TagIO.write(destination, writeTags) }

        if (jpeg != null && coverName != null) {
            val data = jpeg
            val name = coverName
            withContext(Dispatchers.IO) { AppPaths.coverFile(name).writeBytes(data) }
            if (albumKey != null) albumCovers[albumKey] = name
        }

        val finalSize = if (destination.exists()) destination.length() else copied.second
        val track = TrackRecord(
            id = trackId,
            title = title,
            artist = artist,
            album = album,
            albumArtist = albumArtist,
            trackNumber = trackNumber,
            discNumber = discNumber,
            year = year,
            genre = genre,
            durationMs = Math.round(duration * 1000).toInt(),
            format = ext,
            bitrateKbps = tags.bitrateKbps,
            sampleRate = tags.sampleRate,
            fileName = fileName,
            fileSize = finalSize,
            fileHash = copied.first,
            coverName = coverName,
        )

        val duplicates = index.matches(fingerprint(track))
        val position = items.indexOfFirst { it.id == id }
        if (position < 0) return
        update(id) { it.copy(title = title, artist = artist, coverName = coverName) }
        val hit = duplicates.firstOrNull { it.kind != DuplicateKind.SAME_FILE }
        if (hit != null) {
            pending[id] = PendingDuplicate(track, hit.existingId)
            items[position] = items[position].copy(
                state = ImportState.Duplicate(hit.existingId, hit.kind, hit.candidateIsBetterQuality),
            )
            return
        }
        commit(PendingDuplicate(track, ""), position, null)
    }

    private fun commit(waiting: PendingDuplicate, position: Int, replacing: String?) {
        if (!replacing.isNullOrEmpty()) {
            database.track(replacing)?.let { old -> runCatching { AppPaths.trackFile(old.fileName).delete() } }
            database.deleteTrack(replacing)
            index.remove(replacing)
            onTrackRemoved?.invoke(replacing)
        }
        try {
            database.save(waiting.track)
        } catch (_: Exception) {
            items[position] = items[position].copy(state = ImportState.Failed("Не удалось сохранить"))
            summary = summary.copy(failed = summary.failed + 1)
            return
        }
        index.add(fingerprint(waiting.track))
        items[position] = items[position].copy(state = ImportState.Done, trackId = waiting.track.id)
        summary = summary.copy(added = summary.added + 1)
        onTrackAdded?.invoke(waiting.track)
    }

    companion object {
        fun normalizedJpeg(data: ByteArray, maxSide: Int = 1400): ByteArray? {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            val longest = max(bounds.outWidth, bounds.outHeight)
            if (longest <= maxSide && data.size > 1 && (data[0].toInt() and 0xFF) == 0xFF && (data[1].toInt() and 0xFF) == 0xD8) return data
            var sample = 1
            while (longest / (sample * 2) >= maxSide) sample *= 2
            val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample })
                ?: return null
            val side = max(decoded.width, decoded.height)
            val ratio = min(1f, maxSide.toFloat() / side)
            val bitmap = if (ratio < 1f) {
                Bitmap.createScaledBitmap(decoded, max(1, (decoded.width * ratio).toInt()), max(1, (decoded.height * ratio).toInt()), true)
            } else {
                decoded
            }
            val output = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, output)
            if (bitmap !== decoded) bitmap.recycle()
            decoded.recycle()
            return output.toByteArray()
        }
    }
}
