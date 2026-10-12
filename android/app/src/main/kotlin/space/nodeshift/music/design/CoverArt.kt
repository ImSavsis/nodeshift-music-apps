package space.nodeshift.music.design

import android.graphics.BitmapFactory
import android.util.LruCache
import android.view.TextureView
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import space.nodeshift.music.core.CoverMotion
import space.nodeshift.music.data.AppPaths
import java.io.File
import kotlin.math.max
import kotlin.math.min

object CoverImageLoader {
    private val cache = object : LruCache<String, ImageBitmap>(48 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ImageBitmap): Int = value.width * value.height * 4
    }

    private fun key(name: String, maxPixel: Int) = "$name#$maxPixel"

    fun cached(name: String, maxPixel: Int): ImageBitmap? = cache.get(key(name, maxPixel))

    suspend fun image(name: String, maxPixel: Int): ImageBitmap? {
        cached(name, maxPixel)?.let { return it }
        val loaded = withContext(Dispatchers.IO) { decode(AppPaths.coverFile(name), maxPixel) }
        if (loaded != null) cache.put(key(name, maxPixel), loaded)
        return loaded
    }

    fun invalidate(name: String) {
        cache.snapshot().keys.filter { it.startsWith("$name#") }.forEach { cache.remove(it) }
    }

    private fun decode(file: File, maxPixel: Int): ImageBitmap? {
        if (!file.exists()) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (min(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxPixel) sample *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = android.graphics.Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeFile(file.path, options) ?: return null
        val longest = max(decoded.width, decoded.height)
        if (longest <= maxPixel * 3 / 2) return decoded.asImageBitmap()
        val ratio = maxPixel.toFloat() / longest
        val scaled = android.graphics.Bitmap.createScaledBitmap(
            decoded,
            max(1, (decoded.width * ratio).toInt()),
            max(1, (decoded.height * ratio).toInt()),
            true,
        )
        if (scaled !== decoded) decoded.recycle()
        return scaled.asImageBitmap()
    }
}

object MotionBudget {
    private var active = 0
    private const val LIMIT = 3

    fun acquire(): Boolean {
        if (active >= LIMIT) return false
        active += 1
        return true
    }

    fun release() {
        active = max(0, active - 1)
    }
}

@Composable
fun MotionOverlay(motionName: String, modifier: Modifier = Modifier) {
    val reduce = LocalReduceMotion.current
    val lowPower = rememberLowPower()
    var allowed by remember { mutableStateOf(false) }
    var ready by remember { mutableStateOf(false) }
    val alpha by animateFloatAsState(if (ready) 1f else 0f, tween(700), label = "motionFade")
    DisposableEffect(motionName) {
        allowed = MotionBudget.acquire()
        onDispose {
            if (allowed) {
                MotionBudget.release()
                allowed = false
            }
            ready = false
        }
    }
    if (allowed && !reduce && !lowPower) {
        val context = LocalContext.current
        val file = remember(motionName) { AppPaths.motionFile(motionName) }
        val player = remember(motionName) {
            ExoPlayer.Builder(context).build().apply {
                volume = 0f
                repeatMode = Player.REPEAT_MODE_ALL
                videoScalingMode = C.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING
                setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(file)))
                playWhenReady = true
                addListener(object : Player.Listener {
                    override fun onRenderedFirstFrame() {
                        ready = true
                    }
                })
                prepare()
            }
        }
        DisposableEffect(player) {
            onDispose { player.release() }
        }
        AndroidView(
            factory = { TextureView(it).also { view -> player.setVideoTextureView(view) } },
            modifier = modifier.fillMaxSize().graphicsLayer { this.alpha = alpha },
        )
    }
}

@Composable
fun CoverArt(
    coverName: String?,
    modifier: Modifier = Modifier,
    motionName: String? = null,
    radius: Float = Radius.tile,
    live: Boolean = true,
    maxPixel: Int = 480,
) {
    val s = LocalScale.current
    val reduce = LocalReduceMotion.current
    val lowPower = rememberLowPower()
    val shape = RoundedCornerShape(s(radius))
    var image by remember(coverName, maxPixel) {
        mutableStateOf(coverName?.let { CoverImageLoader.cached(it, maxPixel) })
    }
    LaunchedEffect(coverName, maxPixel) {
        image = if (coverName == null) null else CoverImageLoader.image(coverName, maxPixel)
    }
    val drifting = live && !reduce && !lowPower && image != null
    val drift = remember(coverName) { CoverMotion.drift(coverName ?: "") }
    val hasMotion = remember(motionName) { motionName != null && AppPaths.motionFile(motionName).exists() }
    Box(
        modifier
            .aspectRatio(1f)
            .clip(shape)
            .background(Palette.surface)
            .border(1.dp, Palette.line, shape),
    ) {
        val loaded = image
        if (loaded == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CrystalMark(s(28), dim = true)
            }
        } else if (drifting) {
            Box(
                Modifier
                    .fillMaxSize()
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        val offset = CoverMotion.sheenOffset(MotionClock.time.doubleValue, drift).toFloat()
                        translate(left = size.width * offset) {
                            drawRect(
                                brush = Brush.linearGradient(
                                    0.38f to Color.Transparent,
                                    0.5f to Color.White.copy(alpha = 0.18f),
                                    0.62f to Color.Transparent,
                                    start = Offset(size.width * -0.102f, size.height * 0.219f),
                                    end = Offset(size.width * 1.102f, size.height * 0.781f),
                                ),
                                blendMode = BlendMode.SoftLight,
                            )
                        }
                    },
            ) {
                Image(
                    bitmap = loaded,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer {
                            val progress = CoverMotion.driftProgress(MotionClock.time.doubleValue, drift)
                            val scale = CoverMotion.driftScale(progress).toFloat()
                            scaleX = scale
                            scaleY = scale
                            transformOrigin = TransformOrigin(drift.originX.toFloat() / 100f, drift.originY.toFloat() / 100f)
                            translationX = size.width * drift.shiftX.toFloat() / 100f * progress.toFloat()
                            translationY = size.height * drift.shiftY.toFloat() / 100f * progress.toFloat()
                        },
                )
            }
        } else {
            Image(
                bitmap = loaded,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        if (hasMotion && motionName != null) {
            MotionOverlay(motionName)
        }
    }
}
