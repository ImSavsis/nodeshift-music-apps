package space.nodeshift.music.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import space.nodeshift.music.LocalGraph
import space.nodeshift.music.core.DuplicateKind
import space.nodeshift.music.design.Chip
import space.nodeshift.music.design.CoverArt
import space.nodeshift.music.design.Face
import space.nodeshift.music.design.GhostButton
import space.nodeshift.music.design.Icon
import space.nodeshift.music.design.LocalScale
import space.nodeshift.music.design.LucideName
import space.nodeshift.music.design.NText
import space.nodeshift.music.design.PageHeader
import space.nodeshift.music.design.Palette
import space.nodeshift.music.design.PrimaryButton
import space.nodeshift.music.design.Radius
import space.nodeshift.music.design.Spinner
import space.nodeshift.music.design.SurfaceCard
import space.nodeshift.music.design.pressable
import space.nodeshift.music.design.reveal
import space.nodeshift.music.design.surfaceBox
import space.nodeshift.music.imports.DuplicateDecision
import space.nodeshift.music.imports.ImportItem
import space.nodeshift.music.imports.ImportSource
import space.nodeshift.music.imports.ImportState

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ImportRow(item: ImportItem) {
    val s = LocalScale.current
    val importer = LocalGraph.current.importer
    val (text, color) = when (val state = item.state) {
        ImportState.Waiting -> "В очереди" to Palette.dim
        is ImportState.Working -> (state.text + "…") to Palette.muted
        ImportState.Done -> listOfNotNull(item.artist, "Готово").joinToString(" · ") to Palette.dim
        is ImportState.Duplicate -> {
            val base = if (state.kind == DuplicateKind.SAME_TRACK) "Такой трек уже есть" else "Похожий трек уже есть"
            (if (state.betterQuality) "$base (здесь качество лучше)" else base) to Palette.warn
        }
        is ImportState.Skipped -> state.text to Palette.dim
        is ImportState.Failed -> state.text to Palette.danger
    }
    Column(
        Modifier.fillMaxWidth().surfaceBox(s(Radius.tile)).padding(s(12)),
        verticalArrangement = Arrangement.spacedBy(s(10)),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(s(12)), verticalAlignment = Alignment.CenterVertically) {
            CoverArt(item.coverName, Modifier.size(s(40)), live = false, maxPixel = 120)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(s(2))) {
                NText(item.title ?: item.name, Face.InterMedium, 14f, color = Palette.white, maxLines = 1)
                NText(text, Face.MonoRegular, 11f, color = color, maxLines = 2)
            }
            when (item.state) {
                ImportState.Done -> Icon(LucideName.Check, s(18), tint = Palette.ok, stroke = 2f)
                is ImportState.Failed -> Icon(LucideName.CircleAlert, s(18), tint = Palette.danger, stroke = 2f)
                is ImportState.Working -> Spinner(s(18))
                else -> Unit
            }
        }
        if (item.state is ImportState.Duplicate) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(s(8)), verticalArrangement = Arrangement.spacedBy(s(8))) {
                Chip("Пропустить", false) { importer.decide(item.id, DuplicateDecision.Skip) }
                Chip("Оставить оба", false) { importer.decide(item.id, DuplicateDecision.KeepBoth) }
                Chip("Заменить", false) { importer.decide(item.id, DuplicateDecision.Replace) }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ImportScreen() {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val importer = graph.importer
    val toasts = graph.toasts
    val openTab = LocalOpenTab.current
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        importer.add(uris.map { ImportSource(it) })
    }
    val folder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) importer.add(listOf(ImportSource(uri, isTree = true)))
    }
    val archives = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        importer.add(uris.map { ImportSource(it) })
    }
    ScreenScroll {
        PageHeader(
            "Импорт",
            Modifier.reveal(0),
            subtitle = "mp3, flac, wav, ogg, m4a, архивы и папки. Можно сразу много, всё делается на телефоне.",
        )
        Column(
            Modifier
                .fillMaxWidth()
                .reveal(1)
                .drawBehind {
                    drawRoundRect(
                        Palette.line2,
                        cornerRadius = CornerRadius(Radius.card.dp.toPx() * s.factor),
                        style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(7.dp.toPx(), 6.dp.toPx()))),
                    )
                }
                .padding(vertical = s(32), horizontal = s(20)),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(s(12)),
        ) {
            Icon(LucideName.UploadCloud, s(28), tint = Palette.muted, stroke = 1.6f)
            NText("Выбери файлы, папки или архивы", Face.InterMedium, 14f, color = Palette.white, textAlign = TextAlign.Center)
            NText(
                "НАЗВАНИЕ, ИСПОЛНИТЕЛЬ, АЛЬБОМ И ОБЛОЖКА ПОДТЯНУТСЯ САМИ",
                Face.MonoRegular,
                10.5f,
                color = Palette.dim,
                tracking = 0.12f,
                textAlign = TextAlign.Center,
            )
        }
        FlowRow(
            Modifier.padding(top = s(18)).reveal(2),
            horizontalArrangement = Arrangement.spacedBy(s(10)),
            verticalArrangement = Arrangement.spacedBy(s(10)),
        ) {
            PrimaryButton("Файлы", icon = LucideName.FileMusic) {
                files.launch(arrayOf("audio/*", "application/ogg", "application/octet-stream"))
            }
            GhostButton("Папку", icon = LucideName.FolderUp) { folder.launch(null) }
            GhostButton("Архив", icon = LucideName.Archive) {
                archives.launch(arrayOf("application/zip", "application/x-zip-compressed", "application/x-7z-compressed", "application/octet-stream"))
            }
        }
        if (importer.items.isNotEmpty()) {
            Column(Modifier.padding(top = s(24)), verticalArrangement = Arrangement.spacedBy(s(8))) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    NText(statusLine(), Face.InterRegular, 12f, color = Palette.muted, modifier = Modifier.weight(1f))
                    if (importer.pendingDuplicates > 0) {
                        NText(
                            "Пропустить все дубликаты",
                            Face.InterMedium,
                            12f,
                            color = Palette.white,
                            modifier = Modifier.pressable(0.6f, 0.98f) { importer.skipAllDuplicates() },
                        )
                    } else if (!importer.isRunning) {
                        NText(
                            "Убрать завершённые",
                            Face.InterMedium,
                            12f,
                            color = Palette.dim,
                            modifier = Modifier.pressable(0.6f, 0.98f) { importer.clearFinished() },
                        )
                    }
                }
                for (item in importer.items) ImportRow(item)
                if (!importer.isRunning && importer.summary.added > 0) {
                    Box(Modifier.padding(top = s(8))) {
                        SurfaceCard(padding = 16f) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                NText(
                                    "Добавлено треков: ${importer.summary.added}",
                                    Face.InterMedium,
                                    14f,
                                    color = Palette.ok,
                                    modifier = Modifier.weight(1f),
                                )
                                GhostButton("К трекам") { openTab(AppTab.Tracks) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun statusLine(): String {
    val importer = LocalGraph.current.importer
    val summary = importer.summary
    val parts = mutableListOf("${importer.items.size} в списке")
    if (summary.added > 0) parts.add("добавлено ${summary.added}")
    if (summary.duplicates > 0) parts.add("дубликатов ${summary.duplicates}")
    if (summary.failed > 0) parts.add("ошибок ${summary.failed}")
    if (summary.ignored > 0) parts.add("лишних файлов ${summary.ignored}")
    return parts.joinToString(" · ")
}
