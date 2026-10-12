package space.nodeshift.music.design

import android.os.Build
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlin.math.min

private val revealDelays = intArrayOf(0, 40, 80, 120, 160)

fun Modifier.reveal(index: Int = 0): Modifier = composed {
    val reduce = LocalReduceMotion.current
    var shown by remember { mutableStateOf(reduce) }
    val delay = revealDelays[min(index, 4).coerceAtLeast(0)]
    val progress by animateFloatAsState(
        targetValue = if (shown) 1f else 0f,
        animationSpec = tween(durationMillis = 420, delayMillis = delay, easing = Motion.ExpoOut),
        label = "reveal",
    )
    LaunchedEffect(Unit) { shown = true }
    this.graphicsLayer {
        alpha = progress
        translationY = (1f - progress) * 8.dp.toPx()
        if (Build.VERSION.SDK_INT >= 31 && progress < 0.999f) {
            val radius = (1f - progress) * 4.dp.toPx()
            renderEffect = if (radius > 0.5f) BlurEffect(radius, radius, TileMode.Decal) else null
        } else {
            renderEffect = null
        }
    }
}

fun Modifier.stagger(index: Int, rise: Float = 16f, step: Int = 40): Modifier = composed {
    val reduce = LocalReduceMotion.current
    var shown by remember { mutableStateOf(reduce) }
    val progress by animateFloatAsState(
        targetValue = if (shown) 1f else 0f,
        animationSpec = spring(dampingRatio = 0.56f, stiffness = 500f),
        label = "stagger",
    )
    LaunchedEffect(Unit) {
        delay(min(index, 14).toLong() * step)
        shown = true
    }
    this.graphicsLayer {
        alpha = min(1f, progress * 1.4f)
        translationY = (1f - progress) * rise.dp.toPx()
    }
}
