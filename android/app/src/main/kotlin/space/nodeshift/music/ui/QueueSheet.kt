package space.nodeshift.music.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import space.nodeshift.music.LocalGraph
import space.nodeshift.music.data.TrackRecord
import space.nodeshift.music.design.CapsuleShape
import space.nodeshift.music.design.CoverArt
import space.nodeshift.music.design.EqualizerBars
import space.nodeshift.music.design.Face
import space.nodeshift.music.design.IconToggle
import space.nodeshift.music.design.LocalScale
import space.nodeshift.music.design.LucideName
import space.nodeshift.music.design.NText
import space.nodeshift.music.design.Palette
import space.nodeshift.music.design.Radius
import space.nodeshift.music.design.pressable
import space.nodeshift.music.player.RepeatMode

@Composable
fun QueueSheet() {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val player = graph.player
    val queue = player.queue
    val close = { player.isQueueOpen = false }
    SheetScaffold(player.isQueueOpen, close) {
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .height(maxHeight * 0.8f)
                    .clip(sheetShape())
                    .background(Palette.queue)
                    .border(1.dp, Palette.line2, sheetShape()),
            ) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = s(18), vertical = s(14)),
                    horizontalArrangement = Arrangement.spacedBy(s(4)),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(s(4))) {
                        NText("Очередь", Face.UnboundedSemibold, 14f, color = Palette.white, tracking = -0.025f)
                        NText("${queue.size} в списке · ${player.upcomingCount} далее", Face.MonoRegular, 11f, color = Palette.dim)
                    }
                    IconToggle(LucideName.Shuffle, active = player.shuffle, size = 36f, iconSize = 17f) { player.toggleShuffle() }
                    IconToggle(
                        if (player.repeatMode == RepeatMode.One) LucideName.Repeat1 else LucideName.Repeat,
                        active = player.repeatMode != RepeatMode.Off,
                        size = 36f,
                        iconSize = 17f,
                    ) { player.cycleRepeat() }
                    IconToggle(LucideName.Trash2, size = 36f, iconSize = 17f) { player.clearUpcoming() }
                    IconToggle(LucideName.X, size = 36f, iconSize = 17f, onClick = close)
                }
                val state = rememberLazyListState()
                LaunchedEffect(player.isQueueOpen) {
                    if (player.isQueueOpen && player.currentIndex > 0) state.scrollToItem(max(0, player.currentIndex - 2))
                }
                LazyColumn(
                    Modifier.fillMaxWidth().navigationBarsPadding(),
                    state = state,
                    contentPadding = PaddingValues(horizontal = s(8), vertical = s(0)),
                    verticalArrangement = Arrangement.spacedBy(s(2)),
                ) {
                    itemsIndexed(queue) { index, track -> QueueRow(index, track, index == player.currentIndex, player.currentIndex > index) }
                    item { Box(Modifier.height(s(16))) }
                }
            }
        }
    }
}

private fun max(a: Int, b: Int) = if (a > b) a else b

@Composable
private fun QueueRow(index: Int, track: TrackRecord, isCurrent: Boolean, played: Boolean) {
    val s = LocalScale.current
    val player = LocalGraph.current.player
    Row(
        Modifier
            .fillMaxWidth()
            .graphicsLayer { alpha = if (played) 0.5f else 1f }
            .pressable(0.8f, 0.99f) { player.jump(index) }
            .background(if (isCurrent) Palette.surface2 else androidx.compose.ui.graphics.Color.Transparent, RoundedCornerShape(s(Radius.tile)))
            .padding(horizontal = s(8), vertical = s(6)),
        horizontalArrangement = Arrangement.spacedBy(s(12)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        NText("${index + 1}", Face.MonoRegular, 11f, color = Palette.dim, modifier = Modifier.width(s(22)))
        CoverArt(track.coverName, Modifier.size(s(40)), live = false, maxPixel = 160)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(s(2))) {
            NText(track.title, Face.InterMedium, 14f, color = Palette.white, maxLines = 1)
            NText(track.artist, Face.MonoRegular, 11f, color = Palette.dim, maxLines = 1)
        }
        if (isCurrent) {
            EqualizerBars(player.isPlaying)
        } else {
            IconToggle(LucideName.X, size = 32f, iconSize = 15f) { player.remove(index) }
        }
    }
}
