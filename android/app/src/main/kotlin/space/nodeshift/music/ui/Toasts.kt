package space.nodeshift.music.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import space.nodeshift.music.LocalGraph
import space.nodeshift.music.design.CapsuleShape
import space.nodeshift.music.design.Face
import space.nodeshift.music.design.LocalScale
import space.nodeshift.music.design.Motion
import space.nodeshift.music.design.NText
import space.nodeshift.music.design.Palette
import space.nodeshift.music.design.floatShadow
import space.nodeshift.music.design.pressable

class ToastCenter(private val scope: CoroutineScope) {
    class Toast(val id: Long, val text: String, val actionTitle: String?, val action: (() -> Unit)?)

    val toasts = mutableStateListOf<Toast>()
    private var counter = 0L

    fun show(text: String, actionTitle: String? = null, action: (() -> Unit)? = null) {
        val toast = Toast(++counter, text, actionTitle, action)
        toasts.add(toast)
        while (toasts.size > 3) toasts.removeAt(0)
        scope.launch {
            delay(if (actionTitle == null) 3000 else 6000)
            dismiss(toast.id)
        }
    }

    fun dismiss(id: Long) {
        toasts.removeAll { it.id == id }
    }
}

@Composable
fun ToastHost() {
    val s = LocalScale.current
    val bottomInset = LocalBottomInset.current
    val center = LocalGraph.current.toasts
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = s(16), vertical = 0.dp)
            .padding(bottom = bottomInset + s(12)),
        verticalArrangement = Arrangement.spacedBy(s(8), Alignment.Bottom),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        for (toast in center.toasts.toList()) {
            key(toast.id) {
                val state = remember { MutableTransitionState(false).apply { targetState = true } }
                AnimatedVisibility(
                    visibleState = state,
                    enter = fadeIn(Motion.expoOut(220)) + slideInVertically(Motion.expoOut(220)) { it / 2 } + scaleIn(Motion.expoOut(220), 0.96f),
                    exit = fadeOut(Motion.expoOut(220)) + scaleOut(Motion.expoOut(220), 0.96f),
                ) {
                    Row(
                        Modifier
                            .widthIn(max = s(420))
                            .floatShadow(CapsuleShape, 12.dp)
                            .background(Palette.toast, CapsuleShape)
                            .border(1.dp, Palette.line2, CapsuleShape)
                            .padding(horizontal = s(18), vertical = s(12)),
                        horizontalArrangement = Arrangement.spacedBy(s(12)),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        NText(toast.text, Face.InterMedium, 13.5f, color = Palette.white)
                        val title = toast.actionTitle
                        val action = toast.action
                        if (title != null && action != null) {
                            NText(
                                title,
                                Face.InterSemibold,
                                13.5f,
                                color = Palette.white,
                                underline = true,
                                modifier = Modifier.pressable(0.6f, 0.97f) {
                                    action()
                                    center.dismiss(toast.id)
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}
