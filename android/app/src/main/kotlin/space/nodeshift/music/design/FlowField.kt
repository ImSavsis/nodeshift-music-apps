package space.nodeshift.music.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

class FlowSimulation {
    private var homeX = FloatArray(0)
    private var homeY = FloatArray(0)
    private var posX = FloatArray(0)
    private var posY = FloatArray(0)
    private var phase = FloatArray(0)
    private var ease = FloatArray(0)
    private var depth = FloatArray(0)
    private var builtWidth = 0f
    private var builtHeight = 0f
    private var builtScale = 0f
    private var lastTime = Double.NaN
    var clock = 0.0
        private set

    private fun randomFrom(n: Double): Float {
        val s = sin(12.9898 * n + 4.1414) * 43758.5453
        return (s - floor(s)).toFloat()
    }

    fun rebuild(width: Float, height: Float, scale: Float, dp: Float) {
        if (width == builtWidth && height == builtHeight && scale == builtScale) return
        builtWidth = width
        builtHeight = height
        builtScale = scale
        val widthDp = width / dp
        val step = (if (widthDp < 640) 40f else 48f) * scale * dp
        val margin = (if (widthDp < 640) 16f else 40f) * scale * dp
        val usable = min(width - 2 * margin, 1152f * scale * dp)
        val cols = max(2, floor(usable / step).toInt() + 1)
        val rows = kotlin.math.ceil(height / step).toInt() + 1
        val startX = (width - (cols - 1) * step) / 2
        val startY = (height - (rows - 1) * step) / 2
        val total = cols * rows
        homeX = FloatArray(total)
        homeY = FloatArray(total)
        posX = FloatArray(total)
        posY = FloatArray(total)
        phase = FloatArray(total)
        ease = FloatArray(total)
        depth = FloatArray(total)
        var n = 0
        for (row in 0 until rows) {
            for (col in 0 until cols) {
                val rnd = randomFrom(n.toDouble())
                val x = startX + col * step
                val y = startY + row * step
                homeX[n] = x
                homeY[n] = y
                posX[n] = x
                posY[n] = y
                phase[n] = rnd * (Math.PI * 2).toFloat()
                ease[n] = 0.06f + 0.05f * rnd
                depth[n] = rnd
                n += 1
            }
        }
    }

    fun advance(now: Double) {
        val dt = min(0.05, max(0.0, now - (if (lastTime.isNaN()) now else lastTime)))
        lastTime = now
        clock += dt
    }

    fun draw(scope: DrawScope, animate: Boolean, dp: Float) {
        with(scope) {
            val width = size.width
            val height = size.height
            val time = if (animate) clock else 0.0
            val centerX = width * 0.5f
            val centerY = height * 0.45f
            val wobble = 6f * dp
            for (index in homeX.indices) {
                val wobbleX = homeX[index] + wobble * sin(0.6 * time + phase[index]).toFloat()
                val wobbleY = homeY[index] + wobble * cos(0.5 * time + 1.3 * phase[index]).toFloat()
                if (animate) {
                    posX[index] += (wobbleX - posX[index]) * ease[index]
                    posY[index] += (wobbleY - posY[index]) * ease[index]
                } else {
                    posX[index] = wobbleX
                    posY[index] = wobbleY
                }
                var alpha = 0.06f * (0.55f + 0.9f * depth[index])
                val dx = (posX[index] - centerX) / (width * 0.78f)
                val dy = (posY[index] - centerY) / (height * 0.68f)
                val distance = sqrt(dx * dx + dy * dy)
                val mask = if (distance <= 0.38f) 1f else max(0f, 1f - (distance - 0.38f) / 0.54f)
                alpha *= mask
                if (alpha <= 0.002f) continue
                val radius = 2.4f * (0.7f + 0.6f * depth[index]) * 0.5f * dp
                drawCircle(Color(229, 229, 229, (alpha * 255f).toInt().coerceIn(0, 255)), radius, Offset(posX[index], posY[index]))
            }
        }
    }
}

@Composable
fun FlowField(modifier: Modifier = Modifier) {
    val s = LocalScale.current
    val reduce = LocalReduceMotion.current
    val lowPower = rememberLowPower()
    val animate = !reduce && !lowPower
    val simulation = remember { FlowSimulation() }
    val time = rememberFrameTime(active = animate, intervalMillis = 33)
    Canvas(modifier.fillMaxSize()) {
        val now = time.value
        simulation.rebuild(size.width, size.height, s.factor, density)
        if (animate) simulation.advance(now)
        simulation.draw(this, animate, density)
    }
}
