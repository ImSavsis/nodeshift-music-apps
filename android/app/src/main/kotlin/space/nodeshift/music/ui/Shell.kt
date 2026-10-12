package space.nodeshift.music.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import space.nodeshift.music.LocalGraph
import space.nodeshift.music.design.CapsuleShape
import space.nodeshift.music.design.CoverArt
import space.nodeshift.music.design.Face
import space.nodeshift.music.design.Icon
import space.nodeshift.music.design.LocalScale
import space.nodeshift.music.design.LucideName
import space.nodeshift.music.design.Motion
import space.nodeshift.music.design.NText
import space.nodeshift.music.design.Palette
import space.nodeshift.music.design.PlayCircle
import space.nodeshift.music.design.Radius
import space.nodeshift.music.design.edgeRim
import space.nodeshift.music.design.floatShadow
import space.nodeshift.music.design.pressable
import space.nodeshift.music.design.rememberFrameTime
import space.nodeshift.music.design.tappable
import kotlin.math.min

enum class AppTab(val title: String, val icon: LucideName) {
    Tracks("Треки", LucideName.Music2),
    Playlists("Плейлисты", LucideName.ListMusic),
    Favorites("Избранное", LucideName.Heart),
    Importer("Импорт", LucideName.Upload),
}

val LocalBottomInset = compositionLocalOf { 0.dp }
val LocalOpenTab = staticCompositionLocalOf<(AppTab) -> Unit> { {} }
val LocalOpenStorage = staticCompositionLocalOf<() -> Unit> { {} }

@Composable
fun topInset(): Dp = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()

@Composable
fun ScreenScroll(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val s = LocalScale.current
    Column(
        modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = s(16))
            .padding(top = topInset() + s(22), bottom = LocalBottomInset.current + s(24)),
        content = content,
    )
}

@Composable
fun <T> rememberLast(value: T?): T? {
    var last by remember { mutableStateOf(value) }
    if (value != null) last = value
    return last
}

@Composable
fun SheetScaffold(visible: Boolean, onDismiss: () -> Unit, content: @Composable BoxScope.() -> Unit) {
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(visible, enter = fadeIn(Motion.fade(250)), exit = fadeOut(Motion.fade(220))) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.6f)).tappable(onClick = onDismiss))
        }
        AnimatedVisibility(
            visible,
            modifier = Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(Motion.expoOut(340)) { it },
            exit = slideOutVertically(Motion.expoOut(260)) { it },
        ) {
            Box(content = content)
        }
    }
}

@Composable
fun sheetShape(): RoundedCornerShape {
    val s = LocalScale.current
    return RoundedCornerShape(topStart = s(Radius.card), topEnd = s(Radius.card))
}

@Composable
fun BottomBar(tab: AppTab, moreActive: Boolean, onSelect: (AppTab) -> Unit, onMore: () -> Unit) {
    val s = LocalScale.current
    Row(
        Modifier
            .fillMaxWidth()
            .background(Palette.bg.copy(alpha = 0.92f))
            .drawBehind { drawLine(Palette.line2, Offset(0f, 0f), Offset(size.width, 0f), 1.dp.toPx()) }
            .navigationBarsPadding()
            .padding(horizontal = s(8))
            .padding(top = s(6), bottom = s(4)),
        horizontalArrangement = Arrangement.spacedBy(s(2)),
    ) {
        for (item in AppTab.entries) {
            BarItem(item.icon, item.title, tab == item && !moreActive, Modifier.weight(1f)) { onSelect(item) }
        }
        BarItem(LucideName.Ellipsis, "Ещё", moreActive, Modifier.weight(1f), onMore)
    }
}

@Composable
private fun BarItem(icon: LucideName, title: String, active: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val s = LocalScale.current
    val shape = RoundedCornerShape(s(Radius.nav))
    val tint by animateColorAsState(if (active) Palette.white else Palette.dim, Motion.expoOut(200), label = "barTint")
    val fill by animateColorAsState(if (active) Palette.surface2 else Color.Transparent, Motion.expoOut(200), label = "barFill")
    val border by animateColorAsState(if (active) Palette.line2 else Color.Transparent, Motion.expoOut(200), label = "barBorder")
    Column(
        modifier
            .pressable(0.7f, 0.97f, onClick = onClick)
            .background(fill, shape)
            .border(1.dp, border, shape)
            .edgeRim(s(Radius.nav))
            .padding(vertical = s(7), horizontal = s(2)),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(s(3)),
    ) {
        Icon(icon, s(18), tint = tint, stroke = 1.6f)
        NText(title, Face.InterMedium, 10f, color = tint, maxLines = 1)
    }
}

@Composable
fun MiniPlayer() {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val player = graph.player
    val track = player.current ?: return
    val shape = RoundedCornerShape(s(Radius.card))
    val clock = rememberFrameTime(active = player.isPlaying, intervalMillis = 250)
    Row(
        Modifier
            .padding(horizontal = s(8))
            .floatShadow(shape, 16.dp)
            .clip(shape)
            .background(Palette.playerBar)
            .drawBehind {
                clock.value
                val total = player.duration
                val fraction = if (total > 0) min(1.0, player.time() / total).toFloat() else 0f
                drawRect(Color.White, size = androidx.compose.ui.geometry.Size(size.width * fraction, 2.dp.toPx()))
            }
            .border(1.dp, Palette.line2, shape)
            .padding(horizontal = s(8), vertical = s(8)),
        horizontalArrangement = Arrangement.spacedBy(s(12)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier
                .weight(1f)
                .pressable(0.8f, 0.98f) { player.isFullPlayerOpen = true },
            horizontalArrangement = Arrangement.spacedBy(s(12)),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CoverArt(track.coverName, Modifier.size(s(44)), live = false, maxPixel = 200)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(s(2))) {
                NText(track.title, Face.InterMedium, 14f, color = Palette.white, maxLines = 1)
                NText(track.artist, Face.MonoRegular, 11f, color = Palette.dim, maxLines = 1)
            }
        }
        Box(Modifier.pressable(0.9f, 0.96f) { player.togglePlay() }) {
            PlayCircle(size = 44f, playing = player.isPlaying, iconSize = 18f)
        }
        Box(
            Modifier.size(s(36)).pressable(0.6f, 0.96f) { player.next() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(LucideName.SkipForward, s(18), tint = Palette.white, stroke = 2f, filled = true)
        }
    }
}

enum class MoreItem(val title: String, val icon: LucideName) {
    Wishlist("Вишлист", LucideName.Bookmark),
    Storage("Хранилище", LucideName.HardDrive),
    Together("Слушать вместе", LucideName.Users),
    Settings("Настройки", LucideName.Settings),
    Login("Войти", LucideName.LogIn),
}

@Composable
fun MoreSheet(
    visible: Boolean,
    loggedIn: Boolean,
    loginTitle: String,
    versionLine: String,
    onDismiss: () -> Unit,
    onSelect: (MoreItem) -> Unit,
) {
    val s = LocalScale.current
    SheetScaffold(visible, onDismiss) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(sheetShape())
                .background(Palette.sheet)
                .border(1.dp, Palette.line2, sheetShape())
                .navigationBarsPadding()
                .padding(horizontal = s(12))
                .padding(bottom = s(8)),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(s(4)),
        ) {
            Box(Modifier.padding(top = s(10), bottom = s(8)).width(s(36)).height(s(4)).background(Palette.line2, CapsuleShape))
            for (item in MoreItem.entries) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(s(48))
                        .pressable(0.6f, 0.98f) {
                            onDismiss()
                            onSelect(item)
                        }
                        .padding(horizontal = s(14)),
                    horizontalArrangement = Arrangement.spacedBy(s(12)),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        if (item == MoreItem.Login && loggedIn) LucideName.LogOut else item.icon,
                        s(18),
                        tint = Palette.muted,
                        stroke = 1.6f,
                    )
                    NText(if (item == MoreItem.Login) loginTitle else item.title, Face.InterMedium, 14f, color = Palette.white)
                }
            }
            Column(
                Modifier.padding(top = s(10), bottom = s(14)),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(s(4)),
            ) {
                if (versionLine.isNotEmpty()) NText(versionLine, Face.MonoRegular, 11f, color = Palette.dim)
                NText("made by savsis with <3", Face.MonoRegular, 11f, color = Palette.dim)
            }
        }
    }
}
