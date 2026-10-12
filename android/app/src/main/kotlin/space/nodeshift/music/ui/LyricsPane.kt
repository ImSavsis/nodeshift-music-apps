package space.nodeshift.music.ui

import android.os.Build
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import space.nodeshift.music.LocalGraph
import space.nodeshift.music.core.Karaoke
import space.nodeshift.music.core.LyricLine
import space.nodeshift.music.design.Face
import space.nodeshift.music.design.Icon
import space.nodeshift.music.design.LocalScale
import space.nodeshift.music.design.LucideName
import space.nodeshift.music.design.Motion
import space.nodeshift.music.design.NText
import space.nodeshift.music.design.Palette
import space.nodeshift.music.design.rememberFrameTime
import space.nodeshift.music.design.tappable
import space.nodeshift.music.design.CapsuleShape
import space.nodeshift.music.design.reveal
import space.nodeshift.music.lyrics.LyricsState
import kotlin.math.cos
import kotlin.math.min

fun maskStops(fill: Double): List<Pair<Float, Float>> {
    val head = fill * 1.18 - 0.18
    val tail = fill * 1.18
    fun opacity(x: Double): Double = when {
        x <= head -> 1.0
        x >= tail -> 0.0
        else -> 1 - (x - head) / (tail - head)
    }
    val stops = mutableListOf(0f to opacity(0.0).toFloat())
    if (head > 0 && head < 1) stops.add(head.toFloat() to 1f)
    if (tail > 0 && tail < 1) stops.add(tail.toFloat() to 0f)
    stops.add(1f to opacity(1.0).toFloat())
    return stops
}

@Composable
fun KaraokeWord(text: String, fill: Double, size: Float) {
    Box {
        NText(
            text,
            Face.UnboundedSemibold,
            size,
            color = Color.White.copy(alpha = if (fill >= 1) 1f else 0.34f),
            tracking = -0.015f,
            softWrap = false,
        )
        if (fill > 0 && fill < 1) {
            val stops = maskStops(fill)
            NText(
                text,
                Face.UnboundedSemibold,
                size,
                color = Color.White,
                tracking = -0.015f,
                softWrap = false,
                modifier = Modifier
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(
                            Brush.horizontalGradient(colorStops = stops.map { it.first to Color.Black.copy(alpha = it.second) }.toTypedArray()),
                            blendMode = BlendMode.DstIn,
                        )
                    },
            )
        }
    }
}

private class WordItem(val text: String, val spaceAfter: Boolean)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun KaraokeLine(line: LyricLine, nextTime: Double?, index: Int, active: Int, onTap: () -> Unit) {
    val s = LocalScale.current
    val player = LocalGraph.current.player
    val fontSize = 20f
    val items = remember(line) {
        val timed = line.words
        if (!timed.isNullOrEmpty()) {
            timed.mapIndexed { offset, word ->
                WordItem(word.text.trim(), word.text.lastOrNull()?.isWhitespace() == true && offset < timed.size - 1)
            }
        } else {
            val words = Karaoke.syntheticWords(line.text)
            words.mapIndexed { offset, word -> WordItem(word.text, offset < words.size - 1) }
        }
    }
    val style = Karaoke.style(index, active)
    val alpha by animateFloatAsState(style.opacity.toFloat(), tween(550), label = "lineAlpha")
    val scale by animateFloatAsState(style.scale.toFloat(), tween(550), label = "lineScale")
    val blur by animateFloatAsState(style.blur.toFloat(), tween(550), label = "lineBlur")
    val clock = if (index == active) rememberFrameTime(active = true, intervalMillis = 33) else null
    clock?.value
    val fills = if (index == active) {
        Karaoke.fills(line, nextTime, player.time())
    } else {
        List(items.size) { if (index < active) 1.0 else 0.0 }
    }
    FlowRow(
        Modifier
            .fillMaxWidth()
            .tappable(onClick = onTap)
            .padding(vertical = s(fontSize * 0.32f))
            .graphicsLayer {
                this.alpha = alpha
                scaleX = scale
                scaleY = scale
                transformOrigin = TransformOrigin(0f, 0.5f)
                if (Build.VERSION.SDK_INT >= 31 && blur > 0.05f) {
                    val radius = blur * density
                    renderEffect = BlurEffect(radius, radius, TileMode.Decal)
                }
            },
        horizontalArrangement = Arrangement.Start,
        verticalArrangement = Arrangement.spacedBy(s(fontSize * 0.1f)),
    ) {
        items.forEachIndexed { position, item ->
            Box(Modifier.padding(end = if (item.spaceAfter) s(fontSize * 0.3f) else 0.dp)) {
                KaraokeWord(item.text, fills.getOrElse(position) { 0.0 }, fontSize * s.factor)
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LyricsPane(state: LyricsState) {
    when (state) {
        LyricsState.Loading -> Skeleton()
        is LyricsState.Synced -> SyncedLyrics(state.lines)
        is LyricsState.Plain -> PlainLyrics(state.text)
        LyricsState.None -> Empty()
    }
}

@Composable
private fun Skeleton() {
    val s = LocalScale.current
    Column(
        Modifier.fillMaxWidth().padding(horizontal = s(8), vertical = s(40)),
        verticalArrangement = Arrangement.spacedBy(s(24)),
    ) {
        val widths = listOf(0.7f, 0.9f, 0.55f, 0.8f, 0.65f)
        widths.forEachIndexed { index, width ->
            val transition = rememberInfiniteTransition(label = "skeleton")
            val alpha by transition.animateFloat(
                0.07f,
                0.14f,
                infiniteRepeatable(tween(1000, delayMillis = index * 120), RepeatMode.Reverse),
                label = "skeletonAlpha",
            )
            Box(
                Modifier
                    .fillMaxWidth(width)
                    .height(s(24))
                    .background(Color.White.copy(alpha = alpha), CapsuleShape),
            )
        }
    }
}

@Composable
private fun Empty() {
    val s = LocalScale.current
    Column(
        Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(s(12), Alignment.CenterVertically),
    ) {
        Icon(LucideName.MicOff, s(30), tint = Palette.dim, stroke = 1.4f)
        NText("ТЕКСТ НЕ НАЙДЕН", Face.MonoRegular, 12f, color = Palette.dim, tracking = 0.16f)
    }
}

@Composable
private fun PlainLyrics(text: String) {
    val s = LocalScale.current
    val blocks = remember(text) { text.split("\n\n").map { it.trim() }.filter { it.isNotEmpty() } }
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = s(4), vertical = s(64)),
        verticalArrangement = Arrangement.spacedBy(s(28)),
    ) {
        blocks.forEachIndexed { index, block ->
            NText(
                block,
                Face.UnboundedMedium,
                17f,
                color = Color.White.copy(alpha = 0.8f),
                lineHeight = 17f * 1.625f,
                modifier = Modifier.fillMaxWidth().reveal(min(index, 8)),
            )
        }
        NText("ТЕКСТ БЕЗ СИНХРОНИЗАЦИИ", Face.MonoRegular, 11f, color = Palette.dim, tracking = 0.18f)
    }
}

@Composable
private fun SyncedLyrics(lines: List<LyricLine>) {
    val s = LocalScale.current
    val player = LocalGraph.current.player
    val listState = rememberLazyListState()
    var activeIndex by remember(lines) { mutableIntStateOf(Karaoke.activeIndex(lines, player.time())) }
    var userScrollUntil by remember { mutableLongStateOf(0L) }
    LaunchedEffect(lines) {
        while (true) {
            withFrameNanos { }
            val index = Karaoke.activeIndex(lines, player.time())
            if (index != activeIndex) activeIndex = index
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val viewport = constraints.maxHeight
        LaunchedEffect(activeIndex) {
            if (activeIndex >= 0 && System.currentTimeMillis() >= userScrollUntil) {
                listState.animateScrollToItem(activeIndex + 2, scrollOffset = -(viewport * 0.34f).toInt())
            }
        }
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    drawRect(
                        Brush.verticalGradient(
                            0f to Color.Transparent,
                            0.14f to Color.Black,
                            0.82f to Color.Black,
                            1f to Color.Transparent,
                        ),
                        blendMode = BlendMode.DstIn,
                    )
                }
                .pointerInput(Unit) {
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                        userScrollUntil = System.currentTimeMillis() + 4000
                    }
                },
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = s(4)),
        ) {
            item { Box(Modifier.height(with(androidx.compose.ui.platform.LocalDensity.current) { (viewport * 0.34f).toDp() })) }
            item { IntroDots(activeIndex == -1) }
            itemsIndexed(lines) { index, line ->
                KaraokeLine(
                    line = line,
                    nextTime = lines.getOrNull(index + 1)?.time,
                    index = index,
                    active = activeIndex,
                ) { player.seek(line.time) }
            }
            item { Box(Modifier.height(with(androidx.compose.ui.platform.LocalDensity.current) { (viewport * 0.66f).toDp() })) }
        }
    }
}

@Composable
private fun IntroDots(visible: Boolean) {
    val s = LocalScale.current
    val clock = rememberFrameTime(active = visible, intervalMillis = 33)
    val height by animateFloatAsState(if (visible) 1f else 0f, tween(400), label = "introHeight")
    if (height < 0.01f) return
    val time = clock.value
    Row(
        Modifier
            .height(s(24) * height)
            .padding(vertical = s(8) * height)
            .graphicsLayer { alpha = height },
        horizontalArrangement = Arrangement.spacedBy(s(8)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        for (index in 0 until 3) {
            val phase = ((time - index * 0.15) % 1.2) / 1.2
            val wave = (0.5 - 0.5 * cos(phase * 2 * Math.PI)).toFloat()
            Box(
                Modifier
                    .size(s(10))
                    .graphicsLayer {
                        val scale = 0.6f + 0.4f * wave
                        scaleX = scale
                        scaleY = scale
                        alpha = 0.35f + 0.65f * wave
                    }
                    .background(Color.White, androidx.compose.foundation.shape.CircleShape),
            )
        }
    }
}
