package space.nodeshift.music.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Dp

val LocalInk = compositionLocalOf { Palette.white }

@Composable
fun Ink(color: Color, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalInk provides color, content = content)
}

object IconCache {
    private val storage = HashMap<LucideName, List<Path>>()

    @Synchronized
    fun paths(name: LucideName): List<Path> {
        storage[name]?.let { return it }
        val built = name.nodes.map(::build)
        storage[name] = built
        return built
    }

    private fun polygon(points: String, closed: Boolean): Path {
        val numbers = points.split(' ', ',', '\n', '\t').filter { it.isNotEmpty() }.mapNotNull { it.toFloatOrNull() }
        val path = Path()
        var index = 0
        while (index + 1 < numbers.size) {
            if (index == 0) path.moveTo(numbers[index], numbers[index + 1]) else path.lineTo(numbers[index], numbers[index + 1])
            index += 2
        }
        if (closed) path.close()
        return path
    }

    private fun build(node: IconNode): Path = when (node) {
        is IconNode.PathData -> PathParser().parsePathString(node.d).toPath()
        is IconNode.Circle -> Path().apply { addOval(Rect(Offset(node.cx, node.cy), node.r)) }
        is IconNode.Line -> Path().apply {
            moveTo(node.x1, node.y1)
            lineTo(node.x2, node.y2)
        }
        is IconNode.Polyline -> polygon(node.points, false)
        is IconNode.Polygon -> polygon(node.points, true)
        is IconNode.Rect -> Path().apply {
            val box = Rect(node.x, node.y, node.x + node.width, node.y + node.height)
            if (node.rx > 0f) addRoundRect(RoundRect(box, CornerRadius(node.rx))) else addRect(box)
        }
    }
}

@Composable
fun Icon(
    name: LucideName,
    size: Dp,
    modifier: Modifier = Modifier,
    tint: Color = LocalInk.current,
    stroke: Float = 2f,
    filled: Boolean = false,
) {
    val paths = IconCache.paths(name)
    Canvas(modifier.size(size)) {
        val k = this.size.minDimension / 24f
        scale(k, k, pivot = Offset.Zero) {
            val style = Stroke(width = stroke, cap = StrokeCap.Round, join = StrokeJoin.Round)
            for (path in paths) {
                if (filled) drawPath(path, tint)
                drawPath(path, tint, style = style)
            }
        }
    }
}
