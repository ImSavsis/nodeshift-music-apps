package space.nodeshift.music.core

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

class CubicBezier(val x1: Double, val y1: Double, val x2: Double, val y2: Double) {
    private fun sample(a: Double, b: Double, t: Double): Double {
        val u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    fun valueAt(x: Double): Double {
        if (x <= 0) return 0.0
        if (x >= 1) return 1.0
        var low = 0.0
        var high = 1.0
        var t = x
        for (step in 0 until 60) {
            val current = sample(x1, x2, t)
            if (abs(current - x) < 1e-12) break
            if (current < x) low = t else high = t
            t = (low + high) / 2
        }
        return sample(y1, y2, t)
    }

    companion object {
        val EASE_IN_OUT = CubicBezier(0.42, 0.0, 0.58, 1.0)
        val EXPO_OUT = CubicBezier(0.16, 1.0, 0.3, 1.0)
    }
}

data class CoverDrift(
    val duration: Double,
    val delay: Double,
    val shiftX: Double,
    val shiftY: Double,
    val originX: Double,
    val originY: Double,
    val sheenDelay: Double,
)

object CoverMotion {
    const val SHEEN_PERIOD = 9.0
    const val DRIFT_SCALE_FROM = 1.02
    const val DRIFT_SCALE_TO = 1.14

    fun hash(text: String): Long {
        var value = 0L
        for (unit in text) {
            value = (value * 31 + unit.code) and 0xFFFFFFFFL
        }
        return value
    }

    fun drift(seed: String): CoverDrift {
        val h = hash(seed)
        val signed = h.toInt()
        fun shifted(bits: Int): Int = signed shr bits
        val unsigned = h.toInt().toLong() and 0xFFFFFFFFL
        val signX = if (h and 1L != 0L) 1.0 else -1.0
        val signY = if (h and 2L != 0L) 1.0 else -1.0
        return CoverDrift(
            duration = (18 + unsigned % 13).toDouble(),
            delay = -(shifted(4) % 20).toDouble(),
            shiftX = signX * (1.5 + (unsigned % 3) * 0.6),
            shiftY = signY * (1 + (shifted(2) % 3) * 0.5),
            originX = (30 + shifted(8) % 40).toDouble(),
            originY = (30 + shifted(12) % 40).toDouble(),
            sheenDelay = -(shifted(6) % 9).toDouble(),
        )
    }

    fun driftProgress(time: Double, drift: CoverDrift): Double {
        val local = time - drift.delay
        if (local <= 0) return 0.0
        val cycles = local / drift.duration
        val iteration = floor(cycles).toInt()
        var u = cycles - iteration
        if (iteration % 2 == 1) u = 1 - u
        return CubicBezier.EASE_IN_OUT.valueAt(u)
    }

    fun driftScale(progress: Double): Double = DRIFT_SCALE_FROM + (DRIFT_SCALE_TO - DRIFT_SCALE_FROM) * progress

    fun sheenOffset(time: Double, drift: CoverDrift): Double {
        val local = time - drift.sheenDelay
        val cycles = local / SHEEN_PERIOD
        val u = cycles - floor(cycles)
        if (u < 0.62) return -1.3
        return -1.3 + 2.6 * CubicBezier.EASE_IN_OUT.valueAt((u - 0.62) / 0.38)
    }
}

data class AmbientFrame(val x: Double, val y: Double, val scale: Double)

data class AmbientKeyframes(
    val duration: Double,
    val start: AmbientFrame,
    val middle: AmbientFrame,
    val end: AmbientFrame,
    val speed: Double,
)

object AmbientMotion {
    val blobs = listOf(
        AmbientKeyframes(46.0, AmbientFrame(-4.0, -2.0, 1.0), AmbientFrame(16.0, 12.0, 1.16), AmbientFrame(4.0, 22.0, 0.94), 1.0),
        AmbientKeyframes(58.0, AmbientFrame(2.0, 4.0, 1.05), AmbientFrame(-18.0, -10.0, 0.92), AmbientFrame(-6.0, -20.0, 1.14), 0.82),
        AmbientKeyframes(52.0, AmbientFrame(0.0, 0.0, 0.96), AmbientFrame(-14.0, 16.0, 1.14), AmbientFrame(-22.0, 4.0, 1.0), 1.15),
    )

    const val DEFAULT_BPM = 92.0
    const val IDLE_RATE = 0.12

    fun rate(bpm: Double, playing: Boolean): Double {
        if (!playing) return IDLE_RATE
        val value = (if (bpm > 0) bpm else DEFAULT_BPM) / 100
        return min(1.6, max(0.6, value))
    }

    private fun mix(a: AmbientFrame, b: AmbientFrame, t: Double) =
        AmbientFrame(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.scale + (b.scale - a.scale) * t)

    fun state(keyframes: AmbientKeyframes, time: Double): AmbientFrame {
        val cycles = max(0.0, time) / keyframes.duration
        val iteration = floor(cycles).toInt()
        var u = cycles - iteration
        if (iteration % 2 == 1) u = 1 - u
        return if (u < 0.5) {
            mix(keyframes.start, keyframes.middle, CubicBezier.EASE_IN_OUT.valueAt(u / 0.5))
        } else {
            mix(keyframes.middle, keyframes.end, CubicBezier.EASE_IN_OUT.valueAt((u - 0.5) / 0.5))
        }
    }
}
