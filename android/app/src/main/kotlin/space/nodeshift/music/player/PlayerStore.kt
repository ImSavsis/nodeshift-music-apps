package space.nodeshift.music.player

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.launch
import space.nodeshift.music.data.AppPaths
import space.nodeshift.music.data.LibraryStore
import space.nodeshift.music.data.TrackRecord
import kotlin.math.max

enum class RepeatMode {
    Off,
    All,
    One,
    ;

    val next: RepeatMode
        get() = when (this) {
            Off -> All
            All -> One
            One -> Off
        }
}

class PlayerStore(
    private val context: Context,
    private val library: LibraryStore,
    private val scope: CoroutineScope,
) {
    private var controller: MediaController? = null
    private var waiting: ((MediaController) -> Unit)? = null

    var queueIds by mutableStateOf<List<String>>(emptyList())
        private set
    var currentIndex by mutableIntStateOf(-1)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var duration by mutableDoubleStateOf(0.0)
        private set
    var shuffle by mutableStateOf(false)
        private set
    var repeatMode by mutableStateOf(RepeatMode.Off)
        private set
    var isFullPlayerOpen by mutableStateOf(false)
    var isQueueOpen by mutableStateOf(false)
    var seekToken by mutableIntStateOf(0)
        private set

    var onTrackStarted: ((TrackRecord) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    val queue: List<TrackRecord>
        get() {
            val byId = library.tracks.associateBy { it.id }
            return queueIds.mapNotNull { byId[it] }
        }

    val current: TrackRecord?
        get() {
            val id = queueIds.getOrNull(currentIndex) ?: return null
            return library.track(id)
        }

    val upcomingCount: Int
        get() = if (currentIndex < 0) queueIds.size else max(0, queueIds.size - currentIndex - 1)

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            sync(player, events.contains(Player.EVENT_TIMELINE_CHANGED) || events.contains(Player.EVENT_MEDIA_ITEM_TRANSITION))
            if (events.contains(Player.EVENT_MEDIA_ITEM_TRANSITION) || events.contains(Player.EVENT_POSITION_DISCONTINUITY)) {
                seekToken += 1
            }
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            val id = mediaItem?.mediaId ?: return
            library.track(id)?.let { onTrackStarted?.invoke(it) }
        }

        override fun onPlayerError(error: PlaybackException) {
            onError?.invoke(error.errorCodeName)
            val active = controller ?: return
            if (active.hasNextMediaItem()) {
                active.seekToNextMediaItem()
                active.prepare()
                active.play()
            }
        }
    }

    fun connect() {
        scope.launch {
            val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
            val connected = MediaController.Builder(context, token).buildAsync().await()
            controller = connected
            connected.addListener(listener)
            sync(connected, true)
            waiting?.invoke(connected)
            waiting = null
        }
    }

    private fun sync(player: Player, refreshQueue: Boolean) {
        if (refreshQueue) {
            queueIds = (0 until player.mediaItemCount).map { player.getMediaItemAt(it).mediaId }
        }
        currentIndex = if (player.mediaItemCount == 0) -1 else player.currentMediaItemIndex
        isPlaying = player.playWhenReady && player.playbackState != Player.STATE_ENDED && player.mediaItemCount > 0
        shuffle = player.shuffleModeEnabled
        repeatMode = when (player.repeatMode) {
            Player.REPEAT_MODE_ALL -> RepeatMode.All
            Player.REPEAT_MODE_ONE -> RepeatMode.One
            else -> RepeatMode.Off
        }
        val reported = player.duration
        duration = if (reported != C.TIME_UNSET && reported > 0) {
            reported / 1000.0
        } else {
            current?.durationSeconds ?: 0.0
        }
    }

    private fun withController(block: (MediaController) -> Unit) {
        val active = controller
        if (active != null) block(active) else waiting = block
    }

    fun time(): Double = (controller?.currentPosition ?: 0L) / 1000.0

    private fun mediaItem(track: TrackRecord): MediaItem {
        val metadata = MediaMetadata.Builder()
            .setTitle(track.title)
            .setArtist(track.artist)
            .setAlbumTitle(track.album)
            .setDurationMs(track.durationMs.toLong())
            .apply {
                track.coverName?.let { name ->
                    val file = AppPaths.coverFile(name)
                    if (file.exists()) setArtworkUri(Uri.fromFile(file))
                }
            }
            .build()
        return MediaItem.Builder()
            .setMediaId(track.id)
            .setUri(Uri.fromFile(track.file))
            .setMediaMetadata(metadata)
            .build()
    }

    fun play(track: TrackRecord, list: List<TrackRecord>) {
        val ordered = if (list.any { it.id == track.id }) list else listOf(track) + list
        val start = ordered.indexOfFirst { it.id == track.id }
        withController { active ->
            active.setMediaItems(ordered.map(::mediaItem), start, 0L)
            active.prepare()
            active.play()
        }
    }

    fun togglePlay() {
        withController { active ->
            if (active.mediaItemCount == 0) return@withController
            if (active.playWhenReady && active.playbackState != Player.STATE_ENDED) {
                active.pause()
            } else {
                if (active.playbackState == Player.STATE_ENDED) active.seekTo(0, 0L)
                if (active.playbackState == Player.STATE_IDLE) active.prepare()
                active.play()
            }
        }
    }

    fun resume() {
        if (!isPlaying) togglePlay()
    }

    fun pause() {
        if (isPlaying) togglePlay()
    }

    fun next() {
        withController { active ->
            if (active.hasNextMediaItem()) {
                active.seekToNextMediaItem()
            } else if (repeatMode == RepeatMode.Off) {
                active.pause()
                active.seekTo(0, 0L)
            } else {
                active.seekToDefaultPosition(0)
            }
        }
    }

    fun previous() {
        withController { it.seekToPrevious() }
    }

    fun seek(seconds: Double) {
        withController { active ->
            val limit = if (duration > 0) duration else seconds
            active.seekTo((max(0.0, kotlin.math.min(seconds, limit)) * 1000).toLong())
        }
    }

    fun setShuffle(value: Boolean) {
        shuffle = value
        withController { it.shuffleModeEnabled = value }
    }

    fun toggleShuffle() = setShuffle(!shuffle)

    fun cycleRepeat() {
        val target = repeatMode.next
        repeatMode = target
        withController {
            it.repeatMode = when (target) {
                RepeatMode.Off -> Player.REPEAT_MODE_OFF
                RepeatMode.All -> Player.REPEAT_MODE_ALL
                RepeatMode.One -> Player.REPEAT_MODE_ONE
            }
        }
    }

    fun playNext(track: TrackRecord) {
        if (currentIndex < 0) {
            play(track, listOf(track))
            return
        }
        withController { it.addMediaItem(currentIndex + 1, mediaItem(track)) }
    }

    fun addToQueue(track: TrackRecord) {
        if (queueIds.isEmpty()) {
            play(track, listOf(track))
            return
        }
        withController { it.addMediaItem(mediaItem(track)) }
    }

    fun remove(index: Int) {
        if (index !in queueIds.indices || index == currentIndex) return
        withController { it.removeMediaItem(index) }
    }

    fun removeTrack(id: String) {
        withController { active ->
            for (index in (0 until active.mediaItemCount).reversed()) {
                if (active.getMediaItemAt(index).mediaId == id) active.removeMediaItem(index)
            }
        }
    }

    fun clearUpcoming() {
        withController { active ->
            if (active.mediaItemCount == 0) return@withController
            val from = max(0, active.currentMediaItemIndex + 1)
            if (from < active.mediaItemCount) active.removeMediaItems(from, active.mediaItemCount)
        }
    }

    fun jump(index: Int) {
        if (index !in queueIds.indices) return
        withController {
            it.seekToDefaultPosition(index)
            it.play()
        }
    }
}
