package space.nodeshift.music.site

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.SystemClock
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import space.nodeshift.music.core.CooldownGate
import space.nodeshift.music.core.PresenceArt
import space.nodeshift.music.core.PresenceFacts
import space.nodeshift.music.core.PresenceOutcome
import space.nodeshift.music.core.PresencePolicy
import space.nodeshift.music.core.PresenceStep
import space.nodeshift.music.data.AppPaths
import space.nodeshift.music.data.Prefs
import space.nodeshift.music.data.TrackRecord
import space.nodeshift.music.design.CoverSource
import space.nodeshift.music.player.PlayerStore
import java.io.ByteArrayOutputStream
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

private data class PresenceSignal(
    val trackId: String?,
    val playing: Boolean,
    val seekToken: Int,
    val account: String?,
    val enabled: Boolean,
)

private class PresenceCapture(val signal: PresenceSignal, val body: JSONObject)

class PresenceReporter(
    private val player: PlayerStore,
    private val site: SiteSession,
    private val sync: SiteSync,
    private val scope: CoroutineScope,
) {
    private val wake = Channel<Unit>(Channel.CONFLATED)
    private val lane = Mutex()
    private val art = LinkedHashMap<String, String>(Prefs.stringMap(ART_KEY))
    private val artGate = CooldownGate(PresencePolicy.ART_COOLDOWN_MS)
    private val uploading = HashSet<String>()
    private var published = false
    private var lastSignal: PresenceSignal? = null
    private var attemptSignal: PresenceSignal? = null
    private var halted: PresenceSignal? = null
    private var lastSentAt = NEVER
    private var lastAttemptAt = NEVER
    private var stallSince = NEVER
    private var failures = 0

    private fun now(): Long = SystemClock.elapsedRealtime()

    private fun since(mark: Long): Long = if (mark < 0L) LONG_AGO_MS else now() - mark

    private fun deviceId(): String {
        Prefs.string("nsm_device_id")?.let { return it }
        val fresh = UUID.randomUUID().toString().lowercase()
        Prefs.putString("nsm_device_id", fresh)
        return fresh
    }

    private fun signal() = PresenceSignal(
        trackId = player.current?.id,
        playing = player.audible,
        seekToken = player.seekToken,
        account = site.user?.id?.value,
        enabled = sync.discordPresence,
    )

    private fun facts(): PresenceFacts {
        val track = player.current
        val live = signal()
        if (halted != null && halted != live) halted = null
        val stalled = player.listening && !player.audible
        if (!stalled) {
            stallSince = NEVER
        } else if (stallSince < 0L) {
            stallSince = now()
        }
        return PresenceFacts(
            hasTrack = track != null && track.title.isNotBlank() && halted == null,
            enabled = sync.discordPresence,
            hasSession = SiteApi.hasSession,
            playing = player.audible,
            published = published,
            stalledForMs = if (stalled) since(stallSince) else -1L,
            failures = failures,
            sinceSendMs = since(lastSentAt),
            sinceAttemptMs = since(lastAttemptAt),
            changed = live != lastSignal,
            newerThanAttempt = live != attemptSignal,
        )
    }

    fun start() {
        scope.launch { snapshotFlow { Pair(signal(), player.listening) }.collect { wake.trySend(Unit) } }
        scope.launch { loop() }
    }

    fun stopNow() {
        scope.launch { retireNow() }
    }

    suspend fun retireNow() {
        halted = signal()
        lane.withLock { if (published) retire() }
    }

    private suspend fun loop() {
        while (true) {
            withTimeoutOrNull(PresencePolicy.waitMillis(facts())) { wake.receive() }
            val gap = PresencePolicy.gapMillis(since(lastAttemptAt))
            if (gap > 0L) delay(gap)
            try {
                lane.withLock { tick() }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                failures += 1
                lastAttemptAt = now()
            }
        }
    }

    private suspend fun tick() {
        when (PresencePolicy.decide(facts())) {
            PresenceStep.Send -> push()
            PresenceStep.Retire -> retire()
            PresenceStep.Wait -> Unit
        }
    }

    private suspend fun push() {
        lastAttemptAt = now()
        attemptSignal = signal()
        var captured: PresenceCapture? = null
        val outcome = SiteApi.publishPresence {
            captured = capture()
            captured?.body
        }
        val sent = captured
        if (sent != null) attemptSignal = sent.signal
        if (outcome == PresenceOutcome.Retry) {
            failures += 1
            return
        }
        failures = 0
        if (sent == null) return
        lastSignal = sent.signal
        lastSentAt = now()
        if (outcome == PresenceOutcome.Delivered) published = true
    }

    private suspend fun retire() {
        lastAttemptAt = now()
        attemptSignal = signal()
        val outcome = SiteApi.publishPresence { JSONObject().put("stop", true).put("device", deviceId()) }
        if (outcome == PresenceOutcome.Retry) {
            failures += 1
        } else {
            published = false
            lastSignal = null
            failures = 0
        }
    }

    private fun capture(): PresenceCapture? {
        val track = player.current ?: return null
        if (track.title.isBlank()) return null
        val live = signal()
        val body = JSONObject()
            .put("device", deviceId())
            .put("platform", "android")
            .put("playing", live.playing)
            .put("title", track.title)
            .put("artist", track.artist)
            .put("album", track.album ?: "")
            .put("position_ms", player.positionMs())
            .put("duration_ms", (player.duration * 1000).toLong())
        cover(track)?.let { body.put("cover", it) }
        track.siteId?.let { body.put("site_id", it) }
        return PresenceCapture(live, body)
    }

    private fun cover(track: TrackRecord): String? {
        val name = track.coverName ?: return null
        val url = when {
            CoverSource.isRemote(name) -> CoverSource.fullUrl(name)
            name.startsWith("site-") -> SiteApi.coverUrl(name.removePrefix("site-"))
            else -> art[name] ?: run {
                upload(name)
                null
            }
        }
        return url?.takeIf { it.startsWith("https://") }
    }

    private fun upload(name: String) {
        if (!artGate.ready(name, now()) || !uploading.add(name)) return
        scope.launch {
            try {
                val jpeg = withContext(Dispatchers.IO) { shrink(name) }
                val url = jpeg?.let { SiteApi.uploadPresenceArt(it) }
                if (url != null && url.startsWith("https://")) {
                    remember(name, url)
                    if (player.current?.coverName == name) lastSignal = null
                } else {
                    artGate.start(name, now())
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                artGate.start(name, now())
            } finally {
                uploading.remove(name)
                wake.trySend(Unit)
            }
        }
    }

    private fun remember(name: String, url: String) {
        art[name] = url
        while (art.size > ART_LIMIT) art.remove(art.keys.first())
        Prefs.putStringMap(ART_KEY, art)
    }

    private fun shrink(name: String): ByteArray? {
        val file = AppPaths.coverFile(name)
        if (!file.exists()) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        for (side in intArrayOf(600, 360)) {
            val bitmap = decode(file.path, bounds.outWidth, bounds.outHeight, side) ?: continue
            try {
                encode(bitmap)?.let { return it }
            } finally {
                bitmap.recycle()
            }
        }
        return null
    }

    private fun decode(path: String, width: Int, height: Int, side: Int): Bitmap? {
        val sample = PresenceArt.sampleSize(width, height, side)
        return try {
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        } catch (_: OutOfMemoryError) {
            null
        }
    }

    private fun encode(bitmap: Bitmap): ByteArray? {
        for (quality in intArrayOf(88, 75, 60)) {
            val out = ByteArrayOutputStream()
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)) return null
            if (out.size() <= PresenceArt.MAX_BYTES) return out.toByteArray()
        }
        return null
    }

    private companion object {
        const val ART_KEY = "nsm_presence_art"
        const val ART_LIMIT = 300
        const val NEVER = -1L
        const val LONG_AGO_MS = 86_400_000L
    }
}
