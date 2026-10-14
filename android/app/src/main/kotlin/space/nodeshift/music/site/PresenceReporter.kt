package space.nodeshift.music.site

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import space.nodeshift.music.data.AppPaths
import space.nodeshift.music.data.Prefs
import space.nodeshift.music.data.TrackRecord
import space.nodeshift.music.design.CoverSource
import space.nodeshift.music.player.PlayerStore
import java.io.ByteArrayOutputStream
import java.util.UUID

class PresenceReporter(
    private val player: PlayerStore,
    private val site: SiteSession,
    private val scope: CoroutineScope,
) {
    private var heartbeat: Job? = null
    private var sentTrack: String? = null
    private val art = HashMap<String, String>()

    private fun enabled(): Boolean = Prefs.bool("nsm_discord_presence", true)

    private fun deviceId(): String {
        Prefs.string("nsm_device_id")?.let { return it }
        val fresh = UUID.randomUUID().toString().lowercase()
        Prefs.putString("nsm_device_id", fresh)
        return fresh
    }

    fun start() {
        scope.launch {
            snapshotFlow { Triple(player.current?.id, player.isPlaying, player.seekToken) }.collect { changed() }
        }
    }

    private fun changed() {
        if (!site.isLoggedIn || !enabled()) {
            heartbeat?.cancel()
            heartbeat = null
            return
        }
        val track = player.current
        if (track == null) {
            heartbeat?.cancel()
            heartbeat = null
            if (sentTrack != null) {
                sentTrack = null
                scope.launch { SiteApi.publishPresence(JSONObject().put("stop", true)) }
            }
            return
        }
        scope.launch { send(track) }
        if (player.isPlaying) {
            if (heartbeat == null) {
                heartbeat = scope.launch {
                    while (true) {
                        delay(15_000)
                        player.current?.let { send(it) }
                    }
                }
            }
        } else {
            heartbeat?.cancel()
            heartbeat = null
        }
    }

    private suspend fun send(track: TrackRecord) {
        sentTrack = track.id
        val body = JSONObject()
            .put("device", deviceId())
            .put("platform", "android")
            .put("playing", player.isPlaying)
            .put("title", track.title)
            .put("artist", track.artist)
            .put("album", track.album ?: "")
            .put("position_ms", (player.time() * 1000).toLong())
            .put("duration_ms", (player.duration * 1000).toLong())
        cover(track)?.let { body.put("cover", it) }
        track.siteId?.let { body.put("site_id", it) }
        SiteApi.publishPresence(body)
    }

    private suspend fun cover(track: TrackRecord): String? {
        val name = track.coverName ?: return null
        if (CoverSource.isRemote(name)) return CoverSource.fullUrl(name)
        if (name.startsWith("site-")) return SiteApi.coverUrl(name.removePrefix("site-"))
        art[name]?.let { return it }
        val jpeg = withContext(Dispatchers.IO) { shrink(name) } ?: return null
        val url = SiteApi.uploadPresenceArt(jpeg) ?: return null
        art[name] = url
        return url
    }

    private fun shrink(name: String): ByteArray? {
        val file = AppPaths.coverFile(name)
        if (!file.exists()) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (minOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 600) sample *= 2
        val bitmap = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        for (quality in intArrayOf(88, 75, 60)) {
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
            if (out.size() <= 580_000) return out.toByteArray()
        }
        return null
    }
}
