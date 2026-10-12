package space.nodeshift.music.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import space.nodeshift.music.LocalGraph
import space.nodeshift.music.design.Chip
import space.nodeshift.music.design.Eyebrow
import space.nodeshift.music.design.Face
import space.nodeshift.music.design.GhostButton
import space.nodeshift.music.design.Icon
import space.nodeshift.music.design.LocalScale
import space.nodeshift.music.design.LucideName
import space.nodeshift.music.design.NText
import space.nodeshift.music.design.PageHeader
import space.nodeshift.music.design.Palette
import space.nodeshift.music.design.PrimaryButton
import space.nodeshift.music.design.ProgressBar
import space.nodeshift.music.design.Spinner
import space.nodeshift.music.design.SurfaceCard
import space.nodeshift.music.design.pluralTracks
import space.nodeshift.music.design.pressable
import space.nodeshift.music.design.reveal
import space.nodeshift.music.site.ListState
import space.nodeshift.music.site.SyncPhase
import kotlinx.coroutines.launch

tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

@Composable
private fun DownloadRow(title: String, state: ListState, onClick: () -> Unit) {
    val s = LocalScale.current
    val phase = state.phase
    val subtitle = when (phase) {
        SyncPhase.Idle -> if (state.total > 0) pluralTracks(state.total) else "пусто"
        SyncPhase.Loading -> "Получаем список…"
        SyncPhase.Downloading -> "${state.done} из ${state.total}"
        SyncPhase.Done -> "Скачано · ${pluralTracks(state.total)}"
        is SyncPhase.Failed -> phase.text
    }
    Row(
        Modifier.fillMaxWidth().padding(vertical = s(10)),
        horizontalArrangement = Arrangement.spacedBy(s(12)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(s(3))) {
            NText(title, Face.InterMedium, 14f, color = Palette.white, maxLines = 1)
            NText(subtitle, Face.MonoRegular, 11f, color = if (phase == SyncPhase.Done) Palette.ok else Palette.dim, maxLines = 1)
            if (phase == SyncPhase.Downloading && state.total > 0) {
                Box(Modifier.padding(top = s(2))) { ProgressBar(state.done.toFloat() / state.total) }
            }
        }
        when (phase) {
            SyncPhase.Loading, SyncPhase.Downloading -> Spinner(s(20))
            SyncPhase.Done -> GhostButton("Обновить", icon = LucideName.RefreshCw, onClick = onClick)
            else -> GhostButton("Скачать", icon = LucideName.Download, enabled = state.total > 0, onClick = onClick)
        }
    }
}

private fun formatBytes(bytes: Long): String {
    val gb = bytes / 1_073_741_824.0
    if (gb >= 1) return "%.1f ГБ".format(gb)
    return "%.0f МБ".format(bytes / 1_048_576.0)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun StorageScreen(onClose: () -> Unit) {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val site = graph.site
    val sync = graph.sync
    val library = graph.library
    val updates = graph.updates
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    LaunchedEffect(site.isLoggedIn) {
        if (site.isLoggedIn) sync.refresh()
    }
    Box(Modifier.fillMaxSize().background(Palette.bg)) {
        ScreenScroll {
            Row(
                Modifier
                    .padding(bottom = s(14))
                    .pressable(0.6f, 0.98f, onClick = onClose),
                horizontalArrangement = Arrangement.spacedBy(s(6)),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(LucideName.ChevronLeft, s(18), tint = Palette.muted, stroke = 2f)
                NText("Назад", Face.InterMedium, 13.5f, color = Palette.muted)
            }
            PageHeader("Хранилище", Modifier.reveal(0), subtitle = "Что лежит на телефоне и что можно скачать с сайта")
            Box(Modifier.padding(bottom = s(14)).reveal(1)) {
                SurfaceCard {
                    Column(verticalArrangement = Arrangement.spacedBy(s(12))) {
                        Eyebrow("Аккаунт NodeShift", bottom = 0f)
                        val user = site.user
                        if (user != null) {
                            NText(
                                user.handle?.let { "@$it" } ?: user.username ?: "Вы вошли",
                                Face.UnboundedSemibold,
                                16f,
                                color = Palette.white,
                            )
                            NText("Плейлисты и лайки с сайта можно скачать на телефон.", Face.InterRegular, 13f, color = Palette.muted)
                            GhostButton("Выйти", icon = LucideName.LogOut) { site.logout() }
                        } else {
                            NText(
                                "Войди через NodeShift SSO, чтобы скачать свои плейлисты и лайки с music.nodeshift.space.",
                                Face.InterRegular,
                                13.5f,
                                color = Palette.muted,
                            )
                            PrimaryButton(if (site.isBusy) "Открываем…" else "Войти", icon = LucideName.LogIn, enabled = !site.isBusy) {
                                context.findActivity()?.let { activity -> scope.launch { site.login(activity) } }
                            }
                            site.lastError?.let { NText(it, Face.InterRegular, 12.5f, color = Palette.danger) }
                        }
                    }
                }
            }
            if (site.isLoggedIn) {
                Box(Modifier.padding(bottom = s(14)).reveal(2)) {
                    SurfaceCard {
                        Column(verticalArrangement = Arrangement.spacedBy(s(4))) {
                            Eyebrow("Скачать с сайта", bottom = 6f)
                            DownloadRow("Понравившиеся", sync.favorites) { scope.launch { sync.downloadFavorites() } }
                            if (sync.playlists.isNotEmpty()) {
                                Box(Modifier.fillMaxWidth().height(s(1)).background(Palette.line))
                                sync.playlists.forEachIndexed { index, playlist ->
                                    DownloadRow(playlist.name, playlist) { scope.launch { sync.downloadPlaylist(playlist.id) } }
                                    if (index != sync.playlists.lastIndex) Box(Modifier.fillMaxWidth().height(s(1)).background(Palette.line))
                                }
                            }
                            if (sync.needsLogin) {
                                Box(Modifier.padding(top = s(6))) {
                                    NText("Сессия устарела. Войди ещё раз.", Face.InterRegular, 12.5f, color = Palette.warn)
                                }
                            }
                            Box(Modifier.padding(top = s(10))) {
                                GhostButton(
                                    if (sync.isRefreshing) "Обновляем…" else "Обновить список",
                                    icon = LucideName.RefreshCw,
                                    enabled = !sync.isRefreshing,
                                ) { scope.launch { sync.refresh() } }
                            }
                        }
                    }
                }
            }
            Box(Modifier.padding(bottom = s(14)).reveal(3)) {
                SurfaceCard {
                    Column(verticalArrangement = Arrangement.spacedBy(s(10))) {
                        Eyebrow("Качество при скачивании", bottom = 0f)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(s(8)), verticalArrangement = Arrangement.spacedBy(s(8))) {
                            Chip("Без потерь", sync.lossless) { sync.setLossless(true) }
                            Chip("Быстро (AAC)", !sync.lossless) { sync.setLossless(false) }
                        }
                        NText(
                            if (sync.lossless) {
                                "Оригинальные файлы как загружены (FLAC и т.д.): точнее, но тяжелее."
                            } else {
                                "AAC 192 кбит/с для FLAC и WAV: стартует сразу и весит в 5–6 раз меньше."
                            },
                            Face.InterRegular,
                            12.5f,
                            color = Palette.dim,
                        )
                    }
                }
            }
            Box(Modifier.padding(bottom = s(14)).reveal(4)) {
                SurfaceCard {
                    Column(verticalArrangement = Arrangement.spacedBy(s(6))) {
                        Eyebrow("На телефоне", bottom = 4f)
                        val used = library.tracks.sumOf { it.fileSize }
                        NText("${pluralTracks(library.tracks.size)} · ${formatBytes(used)}", Face.InterMedium, 14f, color = Palette.white)
                    }
                }
            }
            Box(Modifier.reveal(4)) {
                SurfaceCard {
                    Column(verticalArrangement = Arrangement.spacedBy(s(10))) {
                        Eyebrow("Обновления", bottom = 0f)
                        NText("Версия ${updates.currentVersion} (${updates.currentBuild})", Face.InterMedium, 14f, color = Palette.white)
                        val manifest = updates.available
                        if (manifest != null) {
                            NText("Доступна ${manifest.version}, сборка ${manifest.build}", Face.InterRegular, 13f, color = Palette.muted)
                            PrimaryButton(
                                if (updates.downloading) "Качаем ${(updates.progress * 100).toInt()}%" else "Обновить",
                                icon = LucideName.Download,
                                enabled = !updates.downloading,
                            ) { scope.launch { updates.downloadAndInstall() } }
                        } else {
                            GhostButton(
                                if (updates.checking) "Проверяем…" else "Проверить обновления",
                                icon = LucideName.RefreshCw,
                                enabled = !updates.checking,
                            ) { scope.launch { updates.check(force = true) } }
                        }
                        updates.failure?.let { NText(it, Face.InterRegular, 12.5f, color = Palette.danger) }
                    }
                }
            }
        }
    }
}
