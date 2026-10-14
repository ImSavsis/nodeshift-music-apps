package space.nodeshift.music.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.launch
import space.nodeshift.music.LocalGraph
import space.nodeshift.music.design.CapsuleShape
import space.nodeshift.music.design.Face
import space.nodeshift.music.design.GhostButton
import space.nodeshift.music.design.Icon
import space.nodeshift.music.design.LocalScale
import space.nodeshift.music.design.LucideName
import space.nodeshift.music.design.NText
import space.nodeshift.music.design.Palette
import space.nodeshift.music.design.PrimaryButton
import space.nodeshift.music.design.Typefaces
import space.nodeshift.music.design.pressable
import space.nodeshift.music.site.BumpPhase
import space.nodeshift.music.site.RoomStatus

private fun qrBitmap(text: String, size: Int = 512): Bitmap {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, mapOf(EncodeHintType.MARGIN to 1))
    val pixels = IntArray(size * size) { index ->
        if (matrix.get(index % size, index / size)) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()
    }
    return Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
}

@Composable
fun TogetherSheet(visible: Boolean, onDismiss: () -> Unit) {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val room = graph.room
    val bump = graph.bump
    val site = graph.site
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var codeInput by remember { mutableStateOf("") }
    var guestName by remember { mutableStateOf(room.savedName()) }
    var busy by remember { mutableStateOf(false) }
    var bumping by remember { mutableStateOf(false) }

    DisposableEffect(visible) {
        onDispose {
            if (bumping) {
                bump.stop()
                bumping = false
            }
        }
    }

    SheetScaffold(visible, { if (!bumping) onDismiss() }) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(sheetShape())
                .background(Palette.modal)
                .border(1.dp, Palette.line2, sheetShape())
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = s(18))
                .padding(top = s(14), bottom = s(20)),
            verticalArrangement = Arrangement.spacedBy(s(16)),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                NText("Слушать вместе", Face.UnboundedSemibold, 16f, color = Palette.white, tracking = -0.025f, modifier = Modifier.weight(1f))
                Box(Modifier.size(s(36)).pressable(0.6f, 0.96f) { onDismiss() }, contentAlignment = Alignment.Center) {
                    Icon(LucideName.X, s(17), tint = Palette.white, stroke = 2f)
                }
            }
            val code = room.code
            when {
                bumping -> BumpContent(
                    phase = bump.phase,
                    text = bump.text,
                    sensor = bump.sensorAvailable,
                    onManual = { bump.triggerManually() },
                    onCancel = {
                        bump.stop()
                        bumping = false
                    },
                )
                code != null -> LiveContent(room.status, code, room.link, room.members.map { it.id to it.name }, room.you, context, onLeave = { room.leave() })
                else -> {
                    NText(
                        "Одна музыка на всех телефонах: создай комнату и покажи QR, введи код или просто коснись телефонов друг о друга.",
                        Face.InterRegular,
                        13.5f,
                        color = Palette.muted,
                    )
                    if (site.isLoggedIn) {
                        PrimaryButton(if (busy) "Создаём…" else "Создать комнату", Modifier.fillMaxWidth(), icon = LucideName.Plus, enabled = !busy) {
                            scope.launch {
                                busy = true
                                room.create()
                                busy = false
                            }
                        }
                    } else {
                        NText("Чтобы создать комнату, войди через сайт. Присоединиться по коду можно и без входа.", Face.InterRegular, 12.5f, color = Palette.dim)
                    }
                    NText("ВОЙТИ В КОМНАТУ", Face.MonoSemibold, 11.5f, color = Palette.dim, tracking = 0.16f)
                    Row(horizontalArrangement = Arrangement.spacedBy(s(10)), verticalAlignment = Alignment.CenterVertically) {
                        CodeField(codeInput, "КОД", Modifier.weight(1f)) { codeInput = it.uppercase().filter { ch -> !ch.isWhitespace() }.take(40) }
                        GhostButton("Войти", enabled = !busy && codeInput.length >= 4) {
                            scope.launch {
                                busy = true
                                room.saveName(guestName)
                                if (room.joinChecked(codeInput, guestName)) codeInput = ""
                                busy = false
                            }
                        }
                    }
                    if (!site.isLoggedIn) {
                        CodeField(guestName, "Твоё имя в комнате", Modifier.fillMaxWidth(), upper = false) { guestName = it.take(24) }
                    }
                    GhostButton("Коснуться телефонами", Modifier.fillMaxWidth(), icon = LucideName.Smartphone) {
                        bumping = true
                        bump.start(site) { joined ->
                            scope.launch {
                                room.joinChecked(joined, guestName)
                                bumping = false
                            }
                        }
                    }
                    room.notice?.let { NText(it, Face.InterRegular, 12.5f, color = Palette.danger) }
                }
            }
        }
    }
}

@Composable
private fun CodeField(value: String, placeholder: String, modifier: Modifier, upper: Boolean = true, onChange: (String) -> Unit) {
    val s = LocalScale.current
    Box(
        modifier
            .height(s(44))
            .background(Palette.surface, CapsuleShape)
            .border(1.dp, Palette.line2, CapsuleShape)
            .padding(horizontal = s(16)),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (value.isEmpty()) NText(placeholder, if (upper) Face.MonoRegular else Face.InterRegular, 15f, color = Palette.dim, maxLines = 1)
        BasicTextField(
            value = value,
            onValueChange = onChange,
            singleLine = true,
            textStyle = TextStyle(
                color = Palette.white,
                fontSize = s.sp(if (upper) 18f else 15f),
                fontFamily = Typefaces.family(if (upper) Face.MonoSemibold else Face.InterRegular),
                letterSpacing = if (upper) s.sp(3f) else s.sp(0f),
            ),
            cursorBrush = SolidColor(Palette.white),
            keyboardOptions = KeyboardOptions(capitalization = if (upper) KeyboardCapitalization.Characters else KeyboardCapitalization.Words),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun LiveContent(
    status: RoomStatus,
    code: String,
    link: String?,
    members: List<Pair<String, String>>,
    you: String?,
    context: Context,
    onLeave: () -> Unit,
) {
    val s = LocalScale.current
    val statusText = when (status) {
        RoomStatus.Idle -> "Не в комнате"
        RoomStatus.Connecting -> "Подключаемся…"
        RoomStatus.Live -> "Вы в комнате"
        RoomStatus.Reconnecting -> "Связь пропала, переподключаемся…"
    }
    Row(horizontalArrangement = Arrangement.spacedBy(s(8)), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(s(8)).background(if (status == RoomStatus.Live) Palette.ok else Palette.warn, androidx.compose.foundation.shape.CircleShape))
        NText(statusText, Face.MonoRegular, 12f, color = Palette.muted)
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        NText(code, Face.MonoSemibold, 30f, color = Palette.white, tracking = 0.3f, modifier = Modifier.weight(1f))
        Box(
            Modifier.size(s(40)).pressable(0.6f, 0.96f) {
                val manager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                manager.setPrimaryClip(ClipData.newPlainText("code", code))
            },
            contentAlignment = Alignment.Center,
        ) {
            Icon(LucideName.Copy, s(18), tint = Palette.white, stroke = 1.8f)
        }
    }
    if (link != null) {
        val image = remember(link) { qrBitmap(link).asImageBitmap() }
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Image(
                bitmap = image,
                contentDescription = null,
                filterQuality = FilterQuality.None,
                modifier = Modifier
                    .size(s(190))
                    .background(Color.White, androidx.compose.foundation.shape.RoundedCornerShape(s(14)))
                    .padding(s(10)),
            )
        }
        NText("Покажи QR второму телефону, отправь ссылку или продиктуй код. Музыка пойдёт синхронно на всех.", Face.InterRegular, 12.5f, color = Palette.dim)
        GhostButton("Поделиться ссылкой", Modifier.fillMaxWidth(), icon = LucideName.Share) {
            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, link)
            context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
    NText("СЛУШАЮТ СЕЙЧАС · ${members.size}", Face.MonoSemibold, 11.5f, color = Palette.dim, tracking = 0.16f)
    for ((id, name) in members) {
        Row(horizontalArrangement = Arrangement.spacedBy(s(12)), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(s(32)).background(Palette.surface, androidx.compose.foundation.shape.CircleShape), contentAlignment = Alignment.Center) {
                Icon(LucideName.Users, s(15), tint = Palette.muted, stroke = 1.8f)
            }
            NText(name, Face.InterMedium, 14f, color = Palette.white, maxLines = 1, modifier = Modifier.weight(1f))
            if (id == you) NText("вы", Face.MonoRegular, 11f, color = Palette.dim)
        }
    }
    GhostButton("Выйти из комнаты", Modifier.fillMaxWidth(), icon = LucideName.LogOut, onClick = onLeave)
}

@Composable
private fun BumpContent(phase: BumpPhase, text: String, sensor: Boolean, onManual: () -> Unit, onCancel: () -> Unit) {
    val s = LocalScale.current
    val title = when (phase) {
        BumpPhase.Idle, BumpPhase.Listening -> "Приложи телефоны друг к другу"
        BumpPhase.Matching -> "Ищем второй телефон…"
        BumpPhase.Joining -> "Подключаем: ${text.ifEmpty { "телефон" }}"
        BumpPhase.Failed -> "Не получилось"
    }
    val subtitle = when (phase) {
        BumpPhase.Idle, BumpPhase.Listening ->
            if (sensor) "Слегка стукни телефонами друг о друга. На втором телефоне тоже открой «Слушать вместе → Коснуться»." else "Датчик движения недоступен. Нажми кнопку одновременно на обоих телефонах."
        BumpPhase.Matching -> "Секунду"
        BumpPhase.Joining -> "Заходим в общую комнату"
        BumpPhase.Failed -> text
    }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(s(16))) {
        Box(Modifier.size(s(120)).background(Palette.surface, CapsuleShape), contentAlignment = Alignment.Center) {
            Icon(LucideName.Smartphone, s(40), tint = Palette.white, stroke = 1.6f)
        }
        NText(title, Face.UnboundedSemibold, 15f, color = Palette.white, textAlign = TextAlign.Center)
        NText(subtitle, Face.InterRegular, 13f, color = Palette.muted, textAlign = TextAlign.Center)
        if (phase == BumpPhase.Listening) {
            GhostButton("Нажать одновременно", Modifier.fillMaxWidth(), icon = LucideName.Radio, onClick = onManual)
        }
        GhostButton("Отмена", Modifier.fillMaxWidth(), onClick = onCancel)
    }
}
