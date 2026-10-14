package space.nodeshift.music.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import space.nodeshift.music.LocalGraph
import space.nodeshift.music.core.PaletteExtractor
import space.nodeshift.music.core.Rgb8
import space.nodeshift.music.data.TrackRecord
import space.nodeshift.music.design.AmbientBackdrop
import space.nodeshift.music.design.CapsuleShape
import space.nodeshift.music.design.CoverArt
import space.nodeshift.music.design.EqualizerBars
import space.nodeshift.music.design.Face
import space.nodeshift.music.design.FormatBadge
import space.nodeshift.music.design.Icon
import space.nodeshift.music.design.IconToggle
import space.nodeshift.music.design.LocalScale
import space.nodeshift.music.design.LucideName
import space.nodeshift.music.design.Motion
import space.nodeshift.music.design.NText
import space.nodeshift.music.design.PaletteProvider
import space.nodeshift.music.design.Palette
import space.nodeshift.music.design.PlayCircle
import space.nodeshift.music.design.Radius
import space.nodeshift.music.design.SeekBar
import space.nodeshift.music.design.formatClock
import space.nodeshift.music.design.pressable
import space.nodeshift.music.design.tappable
import space.nodeshift.music.design.rememberFrameTime
import space.nodeshift.music.player.RepeatMode
import kotlin.math.max
import kotlin.math.min

private enum class PlayerTab { Player, Lyrics }

@Composable
fun FullPlayerScreen() {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val player = graph.player
    val lyrics = graph.lyrics
    val context = LocalContext.current
    val startOnLyrics = remember { context.findActivity()?.intent?.getBooleanExtra("nsm_lyrics", false) == true }
    var tab by remember { mutableStateOf(if (startOnLyrics) PlayerTab.Lyrics else PlayerTab.Player) }
    var drag by remember { mutableFloatStateOf(0f) }
    var palette by remember { mutableStateOf<List<Rgb8>>(PaletteExtractor.fallback) }
    val track = player.current
    LaunchedEffect(track?.id) {
        val active = track ?: return@LaunchedEffect
        palette = PaletteProvider.palette(active.coverName)
        lyrics.ensure(active)
    }
    Box(
        Modifier
            .fillMaxSize()
            .graphicsLayer { translationY = drag }
            .tappable {}
            .background(Palette.bg),
    ) {
        AmbientBackdrop(palette, player.isPlaying)
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            PlayerHeader(
                onClose = { player.isFullPlayerOpen = false },
                onQueue = { player.isQueueOpen = true },
                dragOffset = drag,
                onDrag = { drag = it },
            )
            Row(
                Modifier.align(Alignment.CenterHorizontally).padding(bottom = s(8)),
                horizontalArrangement = Arrangement.spacedBy(s(8)),
            ) {
                TabPill("Плеер", tab == PlayerTab.Player) { tab = PlayerTab.Player }
                TabPill("Текст", tab == PlayerTab.Lyrics) { tab = PlayerTab.Lyrics }
            }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                Crossfade(tab, animationSpec = Motion.fade(300), label = "playerTab") { current ->
                    if (current == PlayerTab.Player) {
                        PlayerPane(track)
                    } else if (track != null) {
                        Column(Modifier.fillMaxSize()) {
                            Box(Modifier.weight(1f).padding(horizontal = s(20))) { LyricsPane(lyrics.state(track)) }
                            Column(Modifier.fillMaxWidth().padding(horizontal = s(20)).padding(bottom = s(8)), verticalArrangement = Arrangement.spacedBy(s(8))) {
                                ProgressRow()
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                                    IconToggle(LucideName.SkipBack, active = true, size = 48f, iconSize = 24f, filled = true) { player.previous() }
                                    Box(Modifier.pressable(0.95f, 0.97f) { player.togglePlay() }) {
                                        PlayCircle(size = 56f, playing = player.isPlaying, iconSize = 24f)
                                    }
                                    IconToggle(LucideName.SkipForward, active = true, size = 48f, iconSize = 24f, filled = true) { player.next() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PlayerHeader(onClose: () -> Unit, onQueue: () -> Unit, dragOffset: Float, onDrag: (Float) -> Unit) {
    val s = LocalScale.current
    val player = LocalGraph.current.player
    var translation by remember { mutableFloatStateOf(0f) }
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = s(14))
            .padding(top = s(8), bottom = s(6))
            .pointerInput(Unit) {
                detectVerticalDragGestures(
                    onDragStart = { translation = 0f },
                    onDragEnd = {
                        if (translation > 100.dp.toPx()) onClose()
                        translation = 0f
                        onDrag(0f)
                    },
                    onDragCancel = {
                        translation = 0f
                        onDrag(0f)
                    },
                ) { _, delta ->
                    translation += delta
                    onDrag(max(0f, translation * 0.5f))
                }
            },
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(s(40)).pressable(0.6f, 0.96f, onClick = onClose), contentAlignment = Alignment.Center) {
            Icon(LucideName.ChevronDown, s(24), tint = Palette.white, stroke = 2f)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(s(6))) {
            Box(Modifier.width(s(36)).height(s(4)).background(Palette.line2, CapsuleShape))
            NText("СЕЙЧАС ИГРАЕТ", Face.MonoRegular, 11f, color = Palette.dim, tracking = 0.2f)
        }
        Box(Modifier.size(s(40)).pressable(0.6f, 0.96f, onClick = onQueue), contentAlignment = Alignment.Center) {
            Icon(LucideName.ListMusic, s(20), tint = Palette.white, stroke = 2f)
            val count = player.upcomingCount
            if (count > 0) {
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = s(2), end = s(0))
                        .background(Color.White, CapsuleShape)
                        .padding(horizontal = s(4))
                        .height(s(16)),
                    contentAlignment = Alignment.Center,
                ) {
                    NText(if (count > 99) "99+" else "$count", Face.MonoSemibold, 9f, color = Palette.ink, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun TabPill(title: String, active: Boolean, onClick: () -> Unit) {
    val s = LocalScale.current
    val fill by animateColorAsState(if (active) Palette.surface2 else Color.Transparent, Motion.fade(200), label = "tabFill")
    val border by animateColorAsState(if (active) Palette.line2 else Color.Transparent, Motion.fade(200), label = "tabBorder")
    val ink by animateColorAsState(if (active) Palette.white else Palette.dim, Motion.fade(200), label = "tabInk")
    Box(
        Modifier
            .pressable(0.7f, 0.97f, onClick = onClick)
            .background(fill, CapsuleShape)
            .border(1.dp, border, CapsuleShape)
            .padding(horizontal = s(20), vertical = s(7)),
    ) {
        NText(title, Face.InterSemibold, 13f, color = ink)
    }
}

@Composable
private fun PlayerPane(track: TrackRecord?) {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val player = graph.player
    val library = graph.library
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val side = max(120f, min(maxWidth.value * 0.84f, maxHeight.value - 330f)).dp
        val coverScale by animateFloatAsState(if (player.isPlaying) 1f else 0.92f, Motion.coverSpring(), label = "coverScale")
        Column(
            Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(s(22), Alignment.CenterVertically),
        ) {
            CoverArt(
                track?.coverName,
                Modifier
                    .size(side)
                    .graphicsLayer {
                        scaleX = coverScale
                        scaleY = coverScale
                    }
                    .shadow(30.dp, RoundedCornerShape(s(Radius.card)), clip = false, ambientColor = Color.Black.copy(0.55f), spotColor = Color.Black.copy(0.7f)),
                motionName = track?.motionName,
                radius = Radius.card,
                maxPixel = 1000,
            )
            Column(Modifier.fillMaxWidth().padding(horizontal = s(20)), verticalArrangement = Arrangement.spacedBy(s(18))) {
                Row(horizontalArrangement = Arrangement.spacedBy(s(12)), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(s(6))) {
                        NText(track?.title ?: "", Face.UnboundedSemibold, 20f, color = Palette.white, tracking = -0.025f, maxLines = 2)
                        Row(horizontalArrangement = Arrangement.spacedBy(s(8)), verticalAlignment = Alignment.CenterVertically) {
                            NText(track?.artist ?: "", Face.MonoRegular, 12f, color = Palette.dim, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                            track?.let { FormatBadge(it.format) }
                        }
                    }
                    EqualizerBars(player.isPlaying)
                }
                ProgressRow()
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    IconToggle(LucideName.Shuffle, active = player.shuffle, size = 44f, iconSize = 19f) { player.toggleShuffle() }
                    IconToggle(LucideName.SkipBack, active = true, size = 48f, iconSize = 24f, filled = true) { player.previous() }
                    Box(Modifier.pressable(0.95f, 0.97f) { player.togglePlay() }) {
                        PlayCircle(size = 64f, playing = player.isPlaying, iconSize = 26f)
                    }
                    IconToggle(LucideName.SkipForward, active = true, size = 48f, iconSize = 24f, filled = true) { player.next() }
                    IconToggle(
                        if (player.repeatMode == RepeatMode.One) LucideName.Repeat1 else LucideName.Repeat,
                        active = player.repeatMode != RepeatMode.Off,
                        size = 44f,
                        iconSize = 19f,
                    ) { player.cycleRepeat() }
                }
                if (track != null) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(s(28), Alignment.CenterHorizontally)) {
                        IconToggle(LucideName.Heart, active = graph.catalog.isFavorite(track), size = 40f, iconSize = 19f, filled = graph.catalog.isFavorite(track)) {
                            graph.catalog.toggleFavorite(track)
                        }
                        IconToggle(LucideName.ListPlus, size = 40f, iconSize = 19f) { library.menuTrack = track }
                        IconToggle(LucideName.Ellipsis, size = 40f, iconSize = 19f) { library.menuTrack = track }
                    }
                }
            }
        }
    }
}

@Composable
private fun ProgressRow() {
    val s = LocalScale.current
    val player = LocalGraph.current.player
    val clock = rememberFrameTime(active = player.isPlaying, intervalMillis = 100)
    clock.value
    val time = player.time()
    Row(horizontalArrangement = Arrangement.spacedBy(s(12)), verticalAlignment = Alignment.CenterVertically) {
        NText(formatClock(time), Face.MonoRegular, 11f, color = Palette.dim, textAlign = TextAlign.End, modifier = Modifier.width(s(40)))
        Box(Modifier.weight(1f)) { SeekBar(time, player.duration) { target -> player.seek(target) } }
        NText(formatClock(player.duration), Face.MonoRegular, 11f, color = Palette.dim, modifier = Modifier.width(s(40)))
    }
}
