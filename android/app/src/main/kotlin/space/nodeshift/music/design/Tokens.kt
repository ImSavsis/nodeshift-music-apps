package space.nodeshift.music.design

import android.content.res.AssetManager
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.max
import kotlin.math.min

object Palette {
    val bg = Color(0xFF0A0A0A)
    val surface = Color.White.copy(alpha = 0.05f)
    val surface2 = Color.White.copy(alpha = 0.09f)
    val line = Color.White.copy(alpha = 0.08f)
    val line2 = Color.White.copy(alpha = 0.14f)
    val text = Color(0xFFE5E5E5)
    val white = Color.White
    val muted = Color.White.copy(alpha = 0.60f)
    val dim = Color.White.copy(alpha = 0.45f)
    val danger = Color(0xFFFF5555)
    val ok = Color(0xFF3FB950)
    val warn = Color(0xFFE3B341)
    val playerBar = Color(0xFF0E0E0E).copy(alpha = 0.96f)
    val sheet = Color(0xFF121212).copy(alpha = 0.97f)
    val modal = Color(0xFF121212)
    val queue = Color(0xFF101010)
    val toast = Color(0xFF161616).copy(alpha = 0.95f)
    val pill = Color(0xFF141414).copy(alpha = 0.90f)
    val ink = Color(0xFF111111)
    val silverTop = Color(0xFFF4F4F6)
    val silverBottom = Color(0xFFCFCFD6)
}

object Radius {
    const val sm = 10f
    const val tile = 12f
    const val nav = 14f
    const val card = 20f
}

enum class Face(val file: String, val weight: FontWeight) {
    InterRegular("Inter-Regular.ttf", FontWeight.Normal),
    InterMedium("Inter-Medium.ttf", FontWeight.Medium),
    InterSemibold("Inter-SemiBold.ttf", FontWeight.SemiBold),
    UnboundedMedium("Unbounded-Medium.ttf", FontWeight.Medium),
    UnboundedSemibold("Unbounded-SemiBold.ttf", FontWeight.SemiBold),
    MonoRegular("JetBrainsMono-Regular.ttf", FontWeight.Normal),
    MonoMedium("JetBrainsMono-Medium.ttf", FontWeight.Medium),
    MonoSemibold("JetBrainsMono-SemiBold.ttf", FontWeight.SemiBold),
}

object Typefaces {
    private val cache = HashMap<Face, FontFamily>()
    private var assets: AssetManager? = null

    fun init(manager: AssetManager) {
        assets = manager
    }

    fun family(face: Face): FontFamily {
        cache[face]?.let { return it }
        val manager = assets ?: return FontFamily.Default
        val built = FontFamily(Font(face.file, manager, face.weight))
        cache[face] = built
        return built
    }
}

@Immutable
class Scale(val factor: Float = 1f) {
    operator fun invoke(value: Float): Dp = (value * factor).dp

    operator fun invoke(value: Int): Dp = (value * factor).dp

    fun sp(value: Float): TextUnit = (value * factor).sp

    companion object {
        fun forWidth(widthDp: Float): Scale = Scale(min(max(widthDp / 390f, 0.84f), 1.3f))
    }
}

val LocalScale = staticCompositionLocalOf { Scale() }

val LocalReduceMotion = staticCompositionLocalOf { false }

object Motion {
    val ExpoOut = CubicBezierEasing(0.16f, 1f, 0.3f, 1f)
    val Layout = CubicBezierEasing(0.4f, 0f, 0.1f, 1f)
    val Opacity = CubicBezierEasing(0.25f, 0.1f, 0.35f, 1f)
    val EaseInOut = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)

    fun <T> expoOut(millis: Int, delay: Int = 0): FiniteAnimationSpec<T> =
        tween(durationMillis = millis, delayMillis = delay, easing = ExpoOut)

    fun <T> spring(): FiniteAnimationSpec<T> = spring(dampingRatio = 0.56f, stiffness = 500f)

    fun <T> coverSpring(): FiniteAnimationSpec<T> = spring(dampingRatio = 0.742f, stiffness = 220f)

    fun <T> page(): FiniteAnimationSpec<T> = tween(durationMillis = 280, easing = EaseOut)

    fun <T> press(): FiniteAnimationSpec<T> = tween(durationMillis = 120, easing = EaseOut)

    fun <T> fade(millis: Int = 200): FiniteAnimationSpec<T> = tween(durationMillis = millis, easing = EaseOut)
}
