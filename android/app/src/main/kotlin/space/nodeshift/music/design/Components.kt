package space.nodeshift.music.design

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import space.nodeshift.music.core.CubicBezier
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

val CapsuleShape = RoundedCornerShape(percent = 50)

@Composable
fun NText(
    text: String,
    face: Face,
    size: Float,
    modifier: Modifier = Modifier,
    color: Color = LocalInk.current,
    tracking: Float = 0f,
    maxLines: Int = Int.MAX_VALUE,
    textAlign: TextAlign = TextAlign.Start,
    lineHeight: Float? = null,
    underline: Boolean = false,
    softWrap: Boolean = true,
) {
    val s = LocalScale.current
    val style = TextStyle(
        color = color,
        fontSize = s.sp(size),
        fontFamily = Typefaces.family(face),
        fontWeight = face.weight,
        letterSpacing = if (tracking == 0f) TextUnit.Unspecified else (tracking * size * s.factor).sp,
        textAlign = textAlign,
        lineHeight = if (lineHeight != null) s.sp(lineHeight) else TextUnit.Unspecified,
        textDecoration = if (underline) TextDecoration.Underline else null,
    )
    BasicText(
        text = text,
        modifier = modifier,
        style = style,
        overflow = TextOverflow.Ellipsis,
        softWrap = softWrap,
        maxLines = maxLines,
    )
}

fun Modifier.pressable(
    pressedAlpha: Float = 0.7f,
    pressedScale: Float = 0.97f,
    enabled: Boolean = true,
    onClick: () -> Unit,
): Modifier = composed {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val alpha by animateFloatAsState(if (pressed) pressedAlpha else 1f, Motion.press(), label = "pressAlpha")
    val scale by animateFloatAsState(if (pressed) pressedScale else 1f, Motion.press(), label = "pressScale")
    this
        .graphicsLayer {
            this.alpha = alpha
            scaleX = scale
            scaleY = scale
        }
        .clickable(interactionSource = source, indication = null, enabled = enabled, onClick = onClick)
}

fun Modifier.tappable(enabled: Boolean = true, onClick: () -> Unit): Modifier = composed {
    val source = remember { MutableInteractionSource() }
    this.clickable(interactionSource = source, indication = null, enabled = enabled, onClick = onClick)
}

fun Modifier.edgeRim(radius: Dp): Modifier = this.drawWithContent {
    drawContent()
    val stroke = 1.dp.toPx()
    drawRoundRect(
        brush = Brush.verticalGradient(
            0f to Color.White.copy(alpha = 0.16f),
            0.12f to Color.Transparent,
            0.88f to Color.Transparent,
            1f to Color.White.copy(alpha = 0.05f),
        ),
        topLeft = Offset(stroke / 2, stroke / 2),
        size = Size(size.width - stroke, size.height - stroke),
        cornerRadius = CornerRadius(radius.toPx() - stroke / 2),
        style = Stroke(stroke),
    )
}

fun Modifier.surfaceBox(
    radius: Dp,
    fill: Color = Palette.surface,
    border: Color = Palette.line,
): Modifier = this
    .background(fill, RoundedCornerShape(radius))
    .border(1.dp, border, RoundedCornerShape(radius))
    .edgeRim(radius)

fun Modifier.floatShadow(shape: Shape, elevation: Dp = 18.dp): Modifier = this.shadow(
    elevation = elevation,
    shape = shape,
    clip = false,
    ambientColor = Color.Black.copy(alpha = 0.5f),
    spotColor = Color.Black.copy(alpha = 0.7f),
)

@Composable
fun rememberFrameTime(active: Boolean = true, intervalMillis: Long = 33): State<Double> {
    val state = remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(active, intervalMillis) {
        if (!active) return@LaunchedEffect
        var last = 0L
        while (true) {
            withFrameNanos { now ->
                if (now - last >= intervalMillis * 1_000_000L) {
                    last = now
                    state.doubleValue = now / 1_000_000_000.0
                }
            }
        }
    }
    return state
}

@Composable
fun PrimaryButton(
    title: String,
    modifier: Modifier = Modifier,
    icon: LucideName? = null,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val s = LocalScale.current
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val alpha by animateFloatAsState(if (pressed) 0.7f else if (enabled) 1f else 0.5f, Motion.press(), label = "primaryAlpha")
    Row(
        modifier
            .graphicsLayer { this.alpha = alpha }
            .shadow(
                elevation = s(6),
                shape = CapsuleShape,
                clip = false,
                ambientColor = Color.Black.copy(alpha = 0.45f),
                spotColor = Color.Black.copy(alpha = 0.6f),
            )
            .height(s(40))
            .background(Brush.verticalGradient(listOf(Palette.silverTop, Palette.silverBottom)), CapsuleShape)
            .border(
                1.dp,
                Brush.verticalGradient(0f to Color.White.copy(alpha = 0.9f), 0.5f to Color.Transparent, 1f to Color.Transparent),
                CapsuleShape,
            )
            .clickable(interactionSource = source, indication = null, enabled = enabled, onClick = onClick)
            .padding(horizontal = s(18)),
        horizontalArrangement = Arrangement.spacedBy(s(8), Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) Icon(icon, s(16), tint = Palette.ink)
        NText(title, Face.InterSemibold, 13.5f, color = Palette.ink, maxLines = 1)
    }
}

@Composable
fun GhostButton(
    title: String,
    modifier: Modifier = Modifier,
    icon: LucideName? = null,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val s = LocalScale.current
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val alpha by animateFloatAsState(if (pressed) 0.7f else if (enabled) 1f else 0.5f, Motion.press(), label = "ghostAlpha")
    Row(
        modifier
            .graphicsLayer { this.alpha = alpha }
            .height(s(40))
            .background(Palette.surface, CapsuleShape)
            .border(1.dp, Palette.line2, CapsuleShape)
            .clickable(interactionSource = source, indication = null, enabled = enabled, onClick = onClick)
            .padding(horizontal = s(18)),
        horizontalArrangement = Arrangement.spacedBy(s(8), Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) Icon(icon, s(16), tint = Palette.white)
        NText(title, Face.InterSemibold, 13.5f, color = Palette.white, maxLines = 1)
    }
}

@Composable
fun Eyebrow(text: String, modifier: Modifier = Modifier, bottom: Float = 14f) {
    val s = LocalScale.current
    NText(
        text = text.uppercase(),
        face = Face.MonoSemibold,
        size = 11.5f,
        color = Palette.dim,
        tracking = 0.16f,
        modifier = modifier.padding(bottom = s(bottom)),
    )
}

@Composable
fun PageHeader(title: String, modifier: Modifier = Modifier, subtitle: String? = null) {
    val s = LocalScale.current
    Column(modifier.fillMaxWidth().padding(bottom = s(18)), verticalArrangement = Arrangement.spacedBy(s(6))) {
        NText(title, Face.UnboundedSemibold, 20f, color = Palette.white, tracking = -0.02f)
        if (subtitle != null) {
            NText(subtitle, Face.InterRegular, 13.5f, color = Palette.muted)
        }
    }
}

@Composable
fun SurfaceCard(modifier: Modifier = Modifier, padding: Float = 22f, content: @Composable () -> Unit) {
    val s = LocalScale.current
    Column(
        modifier
            .fillMaxWidth()
            .surfaceBox(s(Radius.card))
            .padding(s(padding)),
    ) {
        content()
    }
}

@Composable
fun Chip(title: String, active: Boolean, modifier: Modifier = Modifier, icon: LucideName? = null, onClick: () -> Unit) {
    val s = LocalScale.current
    val background by animateColorAsState(if (active) Color.White else Palette.surface, Motion.fade(), label = "chipBg")
    val border by animateColorAsState(if (active) Color.Transparent else Palette.line2, Motion.fade(), label = "chipBorder")
    val ink by animateColorAsState(if (active) Palette.ink else Palette.muted, Motion.fade(), label = "chipInk")
    Row(
        modifier
            .pressable(0.7f, 0.97f, onClick = onClick)
            .height(s(32))
            .background(background, CapsuleShape)
            .border(1.dp, border, CapsuleShape)
            .padding(horizontal = s(14)),
        horizontalArrangement = Arrangement.spacedBy(s(6)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) Icon(icon, s(14), tint = ink, stroke = 1.8f)
        NText(title, Face.InterMedium, 12.5f, color = ink, maxLines = 1)
    }
}

@Composable
fun IconToggle(
    icon: LucideName,
    modifier: Modifier = Modifier,
    active: Boolean = false,
    size: Float = 36f,
    iconSize: Float = 18f,
    filled: Boolean = false,
    tint: Color? = null,
    onClick: () -> Unit,
) {
    val s = LocalScale.current
    val target = tint ?: if (active) Palette.white else Palette.dim
    val color by animateColorAsState(target, Motion.fade(), label = "toggleTint")
    Box(
        modifier
            .size(s(size))
            .pressable(0.6f, 0.97f, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, s(iconSize), tint = color, stroke = 1.8f, filled = filled)
    }
}

@Composable
fun PlayCircle(modifier: Modifier = Modifier, size: Float = 44f, playing: Boolean = false, iconSize: Float = 18f) {
    val s = LocalScale.current
    Box(
        modifier
            .size(s(size))
            .shadow(
                elevation = s(6),
                shape = CircleShape,
                clip = false,
                ambientColor = Color.Black.copy(alpha = 0.35f),
                spotColor = Color.Black.copy(alpha = 0.5f),
            )
            .background(Brush.verticalGradient(listOf(Palette.silverTop, Palette.silverBottom)), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            if (playing) LucideName.Pause else LucideName.Play,
            s(iconSize),
            modifier = Modifier.graphicsLayer { translationX = if (playing) 0f else s(iconSize).toPx() * 0.05f },
            tint = Palette.ink,
            stroke = 2f,
            filled = true,
        )
    }
}

private val losslessFormats = setOf("flac", "wav", "alac", "aiff")

@Composable
fun FormatBadge(format: String, modifier: Modifier = Modifier) {
    val s = LocalScale.current
    val lossless = losslessFormats.contains(format.lowercase())
    val shape = RoundedCornerShape(4.dp)
    NText(
        text = format.uppercase(),
        face = Face.MonoRegular,
        size = 9.5f,
        color = if (lossless) Palette.white else Palette.dim,
        tracking = 0.05f,
        maxLines = 1,
        softWrap = false,
        modifier = modifier
            .background(if (lossless) Color.White.copy(alpha = 0.10f) else Color.Transparent, shape)
            .border(1.dp, if (lossless) Color.White.copy(alpha = 0.4f) else Palette.line2, shape)
            .padding(horizontal = s(6), vertical = 1.dp),
    )
}

private val barDelays = doubleArrayOf(0.0, 0.15, 0.3, 0.1)
private val barKeyframes = doubleArrayOf(0.25, 1.0, 0.4, 0.9, 0.25)

fun equalizerScale(time: Double, delay: Double): Double {
    val duration = 1 + delay
    val local = max(0.0, time - delay)
    val u = local / duration - floor(local / duration)
    val position = u * 4
    val index = min(3, floor(position).toInt())
    val fraction = position - index
    val eased = CubicBezier.EASE_IN_OUT.valueAt(fraction)
    return barKeyframes[index] + (barKeyframes[index + 1] - barKeyframes[index]) * eased
}

@Composable
fun EqualizerBars(isPlaying: Boolean, modifier: Modifier = Modifier) {
    val s = LocalScale.current
    val reduce = LocalReduceMotion.current
    val time = rememberFrameTime(active = isPlaying && !reduce)
    Canvas(modifier.size(width = s(14), height = s(14))) {
        val t = time.value
        val barWidth = 2.dp.toPx() * s.factor
        val gap = 2.dp.toPx() * s.factor
        for (index in 0 until 4) {
            val scale = if (isPlaying) equalizerScale(t, barDelays[index]).toFloat() else 0.25f
            val barHeight = size.height * scale
            drawRoundRect(
                color = Color.White,
                topLeft = Offset(index * (barWidth + gap), size.height - barHeight),
                size = Size(barWidth, barHeight),
                cornerRadius = CornerRadius(barWidth / 2),
            )
        }
    }
}

@Composable
fun SeekBar(value: Double, total: Double, modifier: Modifier = Modifier, onSeek: (Double) -> Unit) {
    val s = LocalScale.current
    var dragging by remember { mutableStateOf(false) }
    var dragValue by remember { mutableDoubleStateOf(0.0) }
    var widthPx by remember { mutableStateOf(1f) }
    val seek by rememberUpdatedState(onSeek)
    val totalNow by rememberUpdatedState(total)
    val thumbScale by animateFloatAsState(if (dragging) 1.3f else 1f, Motion.fade(150), label = "thumb")
    val current = if (dragging) dragValue else value
    val fraction = if (total > 0) min(1.0, max(0.0, current / total)).toFloat() else 0f
    Box(
        modifier
            .fillMaxWidth()
            .height(s(24))
            .onSizeChanged { widthPx = max(1f, it.width.toFloat()) }
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    dragging = true
                    val width = max(1f, size.width.toFloat())
                    dragValue = (down.position.x / width).coerceIn(0f, 1f) * totalNow
                    val finished = drag(down.id) { change ->
                        dragValue = (change.position.x / width).coerceIn(0f, 1f) * totalNow
                        change.consume()
                    }
                    dragging = false
                    if (finished) seek(dragValue)
                }
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(Modifier.fillMaxWidth().height(s(4)).background(Color.White.copy(alpha = 0.14f), CapsuleShape))
        Box(Modifier.fillMaxWidth(fraction).height(s(4)).background(Color.White, CapsuleShape))
        val thumb = s(12)
        Box(
            Modifier
                .graphicsLayer {
                    val travel = widthPx - thumb.toPx()
                    translationX = max(0f, min(travel, widthPx * fraction - thumb.toPx() / 2))
                    scaleX = thumbScale
                    scaleY = thumbScale
                }
                .size(thumb)
                .background(Color.White, CircleShape),
        )
    }
}

fun formatClock(seconds: Double): String {
    val total = max(0, floor(seconds).toInt())
    return "%d:%02d".format(total / 60, total % 60)
}

fun pluralTracks(count: Int): String {
    val mod10 = count % 10
    val mod100 = count % 100
    if (mod10 == 1 && mod100 != 11) return "$count трек"
    if (mod10 in 2..4 && mod100 !in 12..14) return "$count трека"
    return "$count треков"
}

@Composable
fun Spinner(size: Dp, modifier: Modifier = Modifier, color: Color = Color.White, stroke: Dp = 2.dp) {
    val transition = rememberInfiniteTransition(label = "spin")
    val angle by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(900, easing = LinearEasing), RepeatMode.Restart),
        label = "spinAngle",
    )
    Canvas(modifier.size(size)) {
        val width = stroke.toPx()
        drawArc(
            color = color,
            startAngle = angle,
            sweepAngle = 270f,
            useCenter = false,
            topLeft = Offset(width / 2, width / 2),
            size = Size(this.size.width - width, this.size.height - width),
            style = Stroke(width, cap = StrokeCap.Round),
        )
    }
}

@Composable
fun ProgressBar(fraction: Float, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(3.dp).background(Color.White.copy(alpha = 0.14f), CapsuleShape)) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(3.dp).background(Color.White, CapsuleShape))
    }
}
