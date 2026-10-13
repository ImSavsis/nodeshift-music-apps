package space.nodeshift.music.design

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageShader
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import space.nodeshift.music.core.AmbientMotion
import space.nodeshift.music.core.PaletteExtractor
import space.nodeshift.music.core.Rgb8
import space.nodeshift.music.data.AppPaths
import space.nodeshift.music.net.Net
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

object PaletteProvider {
    private val cache = ConcurrentHashMap<String, List<Rgb8>>()

    fun cached(name: String): List<Rgb8>? = cache[name]

    suspend fun palette(coverName: String?): List<Rgb8> {
        val name = coverName ?: return PaletteExtractor.fallback
        cache[name]?.let { return it }
        val computed = if (CoverSource.isRemote(name)) {
            val bytes = try {
                Net.imageBytes(CoverSource.url(name, 300))
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                null
            }
            withContext(Dispatchers.Default) {
                val pixels = bytes?.let { remotePixels(it) } ?: return@withContext PaletteExtractor.fallback
                PaletteExtractor.extract(pixels)
            }
        } else {
            withContext(Dispatchers.Default) {
                val pixels = pixels(name) ?: return@withContext PaletteExtractor.fallback
                PaletteExtractor.extract(pixels)
            }
        }
        cache[name] = computed
        return computed
    }

    private fun remotePixels(bytes: ByteArray): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (min(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 96) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        return rgba(decoded)
    }

    private fun rgba(decoded: Bitmap): ByteArray {
        val scaled = Bitmap.createScaledBitmap(decoded, 48, 48, true)
        val argb = IntArray(48 * 48)
        scaled.getPixels(argb, 0, 48, 0, 0, 48, 48)
        val rgba = ByteArray(48 * 48 * 4)
        for (index in argb.indices) {
            val value = argb[index]
            rgba[index * 4] = (value shr 16 and 0xFF).toByte()
            rgba[index * 4 + 1] = (value shr 8 and 0xFF).toByte()
            rgba[index * 4 + 2] = (value and 0xFF).toByte()
            rgba[index * 4 + 3] = (value shr 24 and 0xFF).toByte()
        }
        if (scaled !== decoded) scaled.recycle()
        decoded.recycle()
        return rgba
    }

    private fun pixels(name: String): ByteArray? {
        val file = AppPaths.coverFile(name)
        if (!file.exists()) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (min(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 96) sample *= 2
        val decoded = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        return rgba(decoded)
    }
}

private object NoiseTile {
    val shader: ShaderBrush by lazy {
        val size = 220
        val pixels = IntArray(size * size)
        var seed = -7046029254386353131L
        for (index in pixels.indices) {
            seed = seed * 6364136223846793005L + 1442695040888963407L
            val value = (seed ushr 33).toInt() and 0xFF
            pixels[index] = (value shl 24) or (value shl 16) or (value shl 8) or value
        }
        val bitmap = Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
        ShaderBrush(ImageShader(bitmap.asImageBitmap(), TileMode.Repeated, TileMode.Repeated))
    }
}

class AmbientEngine {
    private var lastTime = Double.NaN
    private var rate = 0.5
    val clocks = doubleArrayOf(0.0, 0.0, 0.0)

    fun advance(now: Double, playing: Boolean, bpm: Double) {
        val dt = min(0.1, max(0.0, now - (if (lastTime.isNaN()) now else lastTime)))
        lastTime = now
        val target = AmbientMotion.rate(bpm, playing)
        rate += (target - rate) * (1 - 0.98.pow(dt * 60))
        for (index in clocks.indices) {
            clocks[index] += dt * rate * AmbientMotion.blobs[index].speed
        }
    }
}

@Composable
fun AmbientBackdrop(
    palette: List<Rgb8>,
    playing: Boolean,
    modifier: Modifier = Modifier,
    bpm: Double = AmbientMotion.DEFAULT_BPM,
) {
    val reduce = LocalReduceMotion.current
    val engine = remember { AmbientEngine() }
    val time = rememberFrameTime(active = !reduce, intervalMillis = 33)
    val playingNow = rememberUpdatedState(playing)
    val bpmNow = rememberUpdatedState(bpm)
    val spec = tween<Color>(durationMillis = 1600, easing = FastOutSlowInEasing)
    val padded = if (palette.size >= 3) palette else PaletteExtractor.fallback
    val first = animateColorAsState(Color(padded[0].r, padded[0].g, padded[0].b), spec, label = "ambient0")
    val second = animateColorAsState(Color(padded[1].r, padded[1].g, padded[1].b), spec, label = "ambient1")
    val third = animateColorAsState(Color(padded[2].r, padded[2].g, padded[2].b), spec, label = "ambient2")
    Box(modifier.fillMaxSize()) {
        Canvas(Modifier.fillMaxSize()) {
            val now = time.value
            if (!reduce) engine.advance(now, playingNow.value, bpmNow.value)
            val vmax = max(size.width, size.height) / 100f
            val diameter = 78f * vmax
            val centers = arrayOf(
                Offset(-26f * vmax + diameter / 2, -30f * vmax + diameter / 2),
                Offset(size.width + 28f * vmax - diameter / 2, size.height + 34f * vmax - diameter / 2),
                Offset(size.width + 22f * vmax - diameter / 2, -34f * vmax + diameter / 2),
            )
            val colors = arrayOf(first.value, second.value, third.value)
            for (index in 0 until 3) {
                val frame = AmbientMotion.state(AmbientMotion.blobs[index], engine.clocks[index])
                val center = Offset(
                    centers[index].x + diameter * frame.x.toFloat() / 100f,
                    centers[index].y + diameter * frame.y.toFloat() / 100f,
                )
                val radius = diameter / 2 * frame.scale.toFloat()
                val reach = radius * sqrt(2f) * 0.70f
                val base = colors[index]
                drawCircle(
                    brush = Brush.radialGradient(
                        0f to base.copy(alpha = 0.5f * 0.72f),
                        (0.38f / 0.70f) to base.copy(alpha = 0.18f * 0.72f),
                        1f to base.copy(alpha = 0f),
                        center = center,
                        radius = reach,
                    ),
                    radius = reach,
                    center = center,
                )
            }
            drawRect(
                Brush.verticalGradient(listOf(Palette.bg.copy(alpha = 0.2f), Palette.bg.copy(alpha = 0.7f))),
            )
            drawRect(NoiseTile.shader, alpha = 0.07f, blendMode = BlendMode.Softlight)
        }
    }
}
