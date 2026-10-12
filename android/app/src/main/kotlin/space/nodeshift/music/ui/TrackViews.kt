package space.nodeshift.music.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import space.nodeshift.music.LocalGraph
import space.nodeshift.music.data.TrackRecord
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
import space.nodeshift.music.design.Palette
import space.nodeshift.music.design.PlayCircle
import space.nodeshift.music.design.Radius
import space.nodeshift.music.design.Typefaces
import space.nodeshift.music.design.pressable

@Composable
fun TrackActionsPill(track: TrackRecord, modifier: Modifier = Modifier) {
    val s = LocalScale.current
    val library = LocalGraph.current.library
    Row(
        modifier
            .background(Color.Black.copy(alpha = 0.55f), CapsuleShape)
            .border(1.dp, Palette.line2, CapsuleShape)
            .padding(horizontal = s(2)),
    ) {
        IconToggle(LucideName.Heart, active = track.isFavorite, size = 32f, iconSize = 16f, filled = track.isFavorite) {
            library.toggleFavorite(track.id)
        }
        IconToggle(LucideName.Ellipsis, size = 32f, iconSize = 16f) { library.menuTrack = track }
    }
}

@Composable
fun TrackCard(track: TrackRecord, queue: List<TrackRecord>, modifier: Modifier = Modifier) {
    val s = LocalScale.current
    val player = LocalGraph.current.player
    val isCurrent = player.current?.id == track.id
    val overlay by animateFloatAsState(if (isCurrent) 1f else 0f, Motion.fade(200), label = "cardOverlay")
    Column(modifier, verticalArrangement = Arrangement.spacedBy(s(12))) {
        Box {
            Box(
                Modifier.pressable(0.92f, 0.98f) {
                    if (isCurrent) player.togglePlay() else player.play(track, queue)
                },
            ) {
                CoverArt(track.coverName, Modifier.fillMaxWidth(), motionName = track.motionName)
                Box(
                    Modifier
                        .matchParentSize()
                        .clip(RoundedCornerShape(s(Radius.tile)))
                        .background(Color.Black.copy(alpha = 0.30f * overlay)),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.graphicsLayer {
                            alpha = overlay
                            val scale = 0.9f + 0.1f * overlay
                            scaleX = scale
                            scaleY = scale
                        },
                    ) {
                        PlayCircle(size = 48f, playing = isCurrent && player.isPlaying, iconSize = 20f)
                    }
                }
            }
            TrackActionsPill(track, Modifier.align(Alignment.TopEnd).padding(s(6)))
            if (isCurrent) {
                Box(
                    Modifier
                        .align(Alignment.BottomStart)
                        .padding(s(8))
                        .background(Palette.bg.copy(alpha = 0.8f), CapsuleShape)
                        .border(1.dp, Palette.line2, CapsuleShape)
                        .padding(horizontal = s(8), vertical = s(4)),
                ) {
                    EqualizerBars(player.isPlaying)
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(s(2))) {
            NText(track.title, Face.InterMedium, 14f, color = Palette.white, maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(s(6)), verticalAlignment = Alignment.CenterVertically) {
                NText(track.artist, Face.MonoRegular, 11f, color = Palette.dim, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                FormatBadge(track.format)
            }
        }
    }
}

@Composable
fun TrackRow(track: TrackRecord, queue: List<TrackRecord>, modifier: Modifier = Modifier, rank: Int? = null) {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val player = graph.player
    val library = graph.library
    val isCurrent = player.current?.id == track.id
    val shape = RoundedCornerShape(s(Radius.tile))
    val fill by animateColorAsState(if (isCurrent) Palette.surface2 else Color.Transparent, Motion.fade(200), label = "rowFill")
    val border by animateColorAsState(if (isCurrent) Palette.line2 else Color.Transparent, Motion.fade(200), label = "rowBorder")
    Row(
        modifier
            .fillMaxWidth()
            .pressable(0.85f, 0.99f) { if (isCurrent) player.togglePlay() else player.play(track, queue) }
            .background(fill, shape)
            .border(1.dp, border, shape)
            .padding(horizontal = s(8), vertical = s(8)),
        horizontalArrangement = Arrangement.spacedBy(s(12)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (rank != null) {
            NText("$rank", Face.MonoRegular, 12f, color = Palette.dim, modifier = Modifier.width(s(24)))
        }
        Box {
            CoverArt(track.coverName, Modifier.size(s(44)), live = false, maxPixel = 200)
            if (isCurrent) {
                Box(
                    Modifier.size(s(44)).clip(shape).background(Color.Black.copy(alpha = 0.4f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(if (player.isPlaying) LucideName.Pause else LucideName.Play, s(16), tint = Palette.white, stroke = 2f, filled = true)
                }
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(s(2))) {
            NText(track.title, Face.InterMedium, 14f, color = Palette.white, maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(s(8)), verticalAlignment = Alignment.CenterVertically) {
                NText(track.artist, Face.MonoRegular, 11f, color = Palette.dim, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                FormatBadge(track.format)
            }
        }
        if (isCurrent) EqualizerBars(player.isPlaying)
        IconToggle(LucideName.Heart, active = track.isFavorite, size = 32f, iconSize = 16f, filled = track.isFavorite) {
            library.toggleFavorite(track.id)
        }
        IconToggle(LucideName.Ellipsis, size = 32f, iconSize = 16f) { library.menuTrack = track }
    }
}

@Composable
fun SearchField(text: String, placeholder: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    val s = LocalScale.current
    val focus = LocalFocusManager.current
    var focused by remember { mutableStateOf(false) }
    val fill by animateColorAsState(if (focused) Palette.surface2 else Palette.surface, Motion.fade(200), label = "searchFill")
    val border by animateColorAsState(if (focused) Color.White.copy(alpha = 0.4f) else Palette.line2, Motion.fade(200), label = "searchBorder")
    Row(
        modifier
            .fillMaxWidth()
            .height(s(44))
            .background(fill, CapsuleShape)
            .border(1.dp, border, CapsuleShape)
            .padding(horizontal = s(16)),
        horizontalArrangement = Arrangement.spacedBy(s(10)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(LucideName.Search, s(16), tint = Palette.dim, stroke = 1.8f)
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (text.isEmpty()) NText(placeholder, Face.InterRegular, 15f, color = Palette.dim, maxLines = 1)
            BasicTextField(
                value = text,
                onValueChange = onChange,
                singleLine = true,
                textStyle = TextStyle(
                    color = Palette.white,
                    fontSize = s.sp(15f),
                    fontFamily = Typefaces.family(Face.InterRegular),
                ),
                cursorBrush = SolidColor(Palette.white),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { focus.clearFocus() }),
                modifier = Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused },
            )
        }
        if (text.isNotEmpty()) {
            Box(Modifier.size(s(24)).pressable(0.6f, 0.96f) { onChange("") }, contentAlignment = Alignment.Center) {
                Icon(LucideName.X, s(14), tint = Palette.dim, stroke = 2f)
            }
        }
    }
}
