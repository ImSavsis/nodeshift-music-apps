package space.nodeshift.music.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp

private val gradientA = listOf(Color.White.copy(alpha = 0.95f), Color(0xFFBFC4D0).copy(alpha = 0.55f))
private val gradientB = listOf(Color(0xFFE8EBF2).copy(alpha = 0.8f), Color(0xFF8A90A0).copy(alpha = 0.4f))

@Composable
fun CrystalMark(size: Dp, modifier: Modifier = Modifier, dim: Boolean = false) {
    Canvas(modifier.size(size).alpha(if (dim) 0.55f else 1f)) {
        val k = this.size.minDimension / 96f
        fun polygon(points: List<Pair<Float, Float>>, closed: Boolean): Path {
            val path = Path()
            points.forEachIndexed { index, point ->
                if (index == 0) path.moveTo(point.first * k, point.second * k) else path.lineTo(point.first * k, point.second * k)
            }
            if (closed) path.close()
            return path
        }

        fun fill(path: Path, colors: List<Color>, reversed: Boolean, opacity: Float) {
            val box = path.getBounds()
            val start = if (reversed) Offset(box.right, box.top) else Offset(box.left, box.top)
            val end = if (reversed) Offset(box.left, box.bottom) else Offset(box.right, box.bottom)
            drawPath(path, Brush.linearGradient(colors = colors, start = start, end = end), alpha = opacity)
        }
        fill(polygon(listOf(48f to 6f, 76f to 34f, 48f to 52f), true), gradientA, false, 1f)
        fill(polygon(listOf(48f to 6f, 20f to 34f, 48f to 52f), true), gradientB, true, 1f)
        fill(polygon(listOf(20f to 34f, 48f to 52f, 48f to 90f), true), gradientA, false, 0.7f)
        fill(polygon(listOf(76f to 34f, 48f to 52f, 48f to 90f), true), gradientB, true, 0.8f)
        drawPath(
            polygon(listOf(48f to 6f, 76f to 34f, 48f to 52f, 20f to 34f), true),
            Color.White.copy(alpha = 0.45f),
            style = Stroke(width = 0.8f * k),
        )
        drawPath(
            polygon(listOf(20f to 34f, 48f to 90f, 76f to 34f), false),
            Color.White.copy(alpha = 0.25f),
            style = Stroke(width = 0.8f * k),
        )
    }
}
