package space.nodeshift.music.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridItemSpanScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import space.nodeshift.music.LocalGraph
import space.nodeshift.music.data.FormatFilter
import space.nodeshift.music.data.LibrarySort
import space.nodeshift.music.data.LibraryViewMode
import space.nodeshift.music.data.PlaylistRecord
import space.nodeshift.music.data.TrackRecord
import space.nodeshift.music.design.CapsuleShape
import space.nodeshift.music.design.CoverArt
import space.nodeshift.music.design.CrystalMark
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
import space.nodeshift.music.design.Radius
import space.nodeshift.music.design.SurfaceCard
import space.nodeshift.music.design.pluralTracks
import space.nodeshift.music.design.pressable
import space.nodeshift.music.design.reveal
import space.nodeshift.music.design.stagger

fun Modifier.bleed(extra: Dp): Modifier = this.layout { measurable, constraints ->
    val pad = extra.roundToPx()
    val placeable = measurable.measure(constraints.copy(maxWidth = constraints.maxWidth + pad * 2))
    layout(constraints.maxWidth, placeable.height) { placeable.place(-pad, 0) }
}

@Composable
fun UpdateBanner() {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val updates = graph.updates
    val manifest = updates.available ?: return
    val scope = rememberCoroutineScope()
    Row(
        Modifier
            .fillMaxWidth()
            .padding(bottom = s(18))
            .surfaceBoxCard(s(Radius.card))
            .padding(s(14)),
        horizontalArrangement = Arrangement.spacedBy(s(12)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(LucideName.Download, s(20), tint = Palette.white, stroke = 1.8f)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(s(2))) {
            NText("Доступна версия ${manifest.version}", Face.InterMedium, 14f, color = Palette.white)
            val line = when {
                updates.downloading -> "Скачиваем ${(updates.progress * 100).toInt()}%"
                updates.failure != null -> updates.failure ?: ""
                else -> "сборка ${manifest.build}"
            }
            NText(line, Face.MonoRegular, 11f, color = if (updates.failure != null) Palette.danger else Palette.dim)
        }
        PrimaryButton(if (updates.downloading) "Качаем…" else "Обновить", enabled = !updates.downloading) {
            scope.launch { updates.downloadAndInstall() }
        }
    }
}

private fun Modifier.surfaceBoxCard(radius: Dp): Modifier = this
    .background(Palette.surface, RoundedCornerShape(radius))
    .border(1.dp, Palette.line, RoundedCornerShape(radius))

@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
fun LibraryScreen() {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val library = graph.library
    val player = graph.player
    val openTab = LocalOpenTab.current
    val openStorage = LocalOpenStorage.current
    val list = library.filtered
    val grid = library.viewMode == LibraryViewMode.Grid
    val full: LazyGridItemSpanScope.() -> GridItemSpan = { GridItemSpan(maxLineSpan) }
    LazyVerticalGrid(
        columns = GridCells.Fixed(if (grid) 2 else 1),
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(
            start = s(16),
            end = s(16),
            top = topInset() + s(22),
            bottom = LocalBottomInset.current + s(24),
        ),
        horizontalArrangement = Arrangement.spacedBy(s(14)),
        verticalArrangement = Arrangement.spacedBy(if (grid) s(24) else s(4)),
    ) {
        item(span = full) { UpdateBanner() }
        item(span = full) {
            PageHeader("Треки", Modifier.reveal(0), subtitle = "Вся твоя музыка у тебя на телефоне")
        }
        item(span = full) {
            SearchField(library.query, "Поиск по трекам", { library.query = it }, Modifier.padding(bottom = s(14)).reveal(1))
        }
        item(span = full) {
            Row(Modifier.padding(bottom = s(26)).reveal(2), horizontalArrangement = Arrangement.spacedBy(s(10))) {
                PrimaryButton("Случайная волна", icon = LucideName.Sparkles) {
                    val picked = library.tracks.shuffled().take(40)
                    val first = picked.firstOrNull() ?: return@PrimaryButton
                    player.applyShuffle(true)
                    player.play(first, picked)
                }
                GhostButton("Перемешать", icon = LucideName.Shuffle) {
                    val all = library.filtered.shuffled()
                    val first = all.firstOrNull() ?: return@GhostButton
                    player.applyShuffle(true)
                    player.play(first, all)
                }
            }
        }
        if (library.tracks.isEmpty()) {
            item(span = full) {
                SurfaceCard(Modifier.reveal(3)) {
                    Column(verticalArrangement = Arrangement.spacedBy(s(14))) {
                        CrystalMark(s(40), dim = true)
                        NText("Пока пусто", Face.UnboundedSemibold, 16f, color = Palette.white)
                        NText(
                            "Добавь треки через вкладку «Импорт»: файлы, папки или архивы. Названия, альбомы и обложки подтянутся сами. Или войди через сайт и скачай свои плейлисты и лайки.",
                            Face.InterRegular,
                            13.5f,
                            color = Palette.muted,
                        )
                        PrimaryButton("Открыть импорт", icon = LucideName.Upload) { openTab(AppTab.Importer) }
                        GhostButton("Скачать с сайта", icon = LucideName.CloudDownload) { openStorage() }
                    }
                }
            }
        } else {
            val recent = library.recent
            if (library.query.isEmpty() && recent.isNotEmpty()) {
                item(span = full) {
                    Column(Modifier.padding(bottom = s(26)).reveal(3)) {
                        Eyebrow("Недавно слушали")
                        LazyRow(
                            Modifier.bleed(s(16)),
                            contentPadding = PaddingValues(horizontal = s(16)),
                            horizontalArrangement = Arrangement.spacedBy(s(20)),
                            verticalAlignment = Alignment.Top,
                        ) {
                            items(recent, key = { it.id }) { track -> TrackCard(track, recent, Modifier.width(s(160))) }
                        }
                    }
                }
            }
            item(span = full) {
                Column(Modifier.padding(bottom = s(26)).reveal(4), verticalArrangement = Arrangement.spacedBy(s(8))) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(s(8)), verticalArrangement = Arrangement.spacedBy(s(8))) {
                        for (sort in LibrarySort.entries) Chip(sort.label, library.sort == sort) { library.sort = sort }
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(s(8)), verticalArrangement = Arrangement.spacedBy(s(8))) {
                        for (filter in FormatFilter.entries) Chip(filter.label, library.formatFilter == filter) { library.formatFilter = filter }
                        Chip("Сеткой", library.viewMode == LibraryViewMode.Grid, icon = LucideName.LayoutGrid) {
                            library.changeViewMode(LibraryViewMode.Grid)
                        }
                        Chip("Списком", library.viewMode == LibraryViewMode.List, icon = LucideName.LayoutList) {
                            library.changeViewMode(LibraryViewMode.List)
                        }
                    }
                }
            }
            item(span = full) {
                Eyebrow(if (library.query.isEmpty()) "Библиотека" else "Результаты поиска", Modifier.reveal(4), bottom = if (grid) 0f else 10f)
            }
            if (list.isEmpty()) {
                item(span = full) { NText("Ничего не найдено.", Face.InterRegular, 14f, color = Palette.dim) }
            } else {
                items(list, key = { it.id }) { track ->
                    val position = list.indexOf(track)
                    if (grid) {
                        TrackCard(track, list, Modifier.stagger(position, 16f, 40))
                    } else {
                        TrackRow(track, list, Modifier.stagger(position, 10f, 30))
                    }
                }
            }
        }
    }
}

@Composable
fun FavoritesScreen() {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val library = graph.library
    val player = graph.player
    val openStorage = LocalOpenStorage.current
    val list = library.favorites
    LazyColumn(
        Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(
            start = s(16),
            end = s(16),
            top = topInset() + s(22),
            bottom = LocalBottomInset.current + s(24),
        ),
        verticalArrangement = Arrangement.spacedBy(s(4)),
    ) {
        item {
            PageHeader(
                "Избранное",
                Modifier.reveal(0),
                subtitle = if (list.isEmpty()) "Треки, которые вы отметили" else "${pluralTracks(list.size)}, которые вы отметили",
            )
        }
        item {
            GhostButton("Скачать лайки с сайта", Modifier.padding(bottom = s(18)).reveal(1), icon = LucideName.CloudDownload) { openStorage() }
        }
        if (list.isEmpty()) {
            item {
                NText(
                    "В избранном пока пусто. Нажми на сердце у любого трека.",
                    Face.InterRegular,
                    14f,
                    color = Palette.dim,
                    modifier = Modifier.reveal(1),
                )
            }
        } else {
            item {
                Row(Modifier.padding(bottom = s(22)).reveal(1), horizontalArrangement = Arrangement.spacedBy(s(10))) {
                    PrimaryButton("Слушать", icon = LucideName.Play) {
                        val first = list.firstOrNull() ?: return@PrimaryButton
                        player.applyShuffle(false)
                        player.play(first, list)
                    }
                    GhostButton("Перемешать", icon = LucideName.Shuffle) {
                        val shuffled = list.shuffled()
                        val first = shuffled.firstOrNull() ?: return@GhostButton
                        player.applyShuffle(true)
                        player.play(first, shuffled)
                    }
                }
            }
            items(list, key = { it.id }) { track ->
                TrackRow(track, list, Modifier.stagger(list.indexOf(track), 10f, 30))
            }
        }
    }
}

@Composable
fun PlaylistsScreen() {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val library = graph.library
    val player = graph.player
    val toasts = graph.toasts
    val openStorage = LocalOpenStorage.current
    val scope = rememberCoroutineScope()
    val albums = library.tracks
        .filter { !it.album.isNullOrEmpty() }
        .groupBy { it.album ?: "" }
        .map { it.key to it.value.sortedWith(compareBy({ track -> track.discNumber ?: 1 }, { track -> track.trackNumber ?: 0 })) }
        .sortedBy { it.first.lowercase() }
    val counts by produceState(emptyMap<String, Int>(), library.playlists, library.tracks.size) {
        value = withContext(Dispatchers.IO) { library.playlists.associate { it.id to graph.database.trackIds(it.id).size } }
    }
    val full: LazyGridItemSpanScope.() -> GridItemSpan = { GridItemSpan(maxLineSpan) }
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(
            start = s(16),
            end = s(16),
            top = topInset() + s(22),
            bottom = LocalBottomInset.current + s(24),
        ),
        horizontalArrangement = Arrangement.spacedBy(s(14)),
        verticalArrangement = Arrangement.spacedBy(s(24)),
    ) {
        item(span = full) { PageHeader("Плейлисты", Modifier.reveal(0), subtitle = "Ваши подборки") }
        item(span = full) {
            GhostButton("Скачать плейлисты с сайта", Modifier.padding(bottom = s(8)).reveal(1), icon = LucideName.CloudDownload) { openStorage() }
        }
        item {
            Column(
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    .drawBehind {
                        drawRoundRect(
                            Palette.line2,
                            cornerRadius = CornerRadius(Radius.tile.dp.toPx() * s.factor),
                            style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx()))),
                        )
                    }
                    .pressable(0.7f, 0.97f) { toasts.show("Плейлисты скоро будут") },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(LucideName.Plus, s(24), tint = Palette.muted, stroke = 1.6f)
                Box(Modifier.padding(top = s(10))) { NText("Новый плейлист", Face.InterMedium, 13.5f, color = Palette.muted) }
            }
        }
        items(library.playlists, key = { "p-" + it.id }) { playlist ->
            CollectionTile(
                title = playlist.name,
                subtitle = pluralTracks(counts[playlist.id] ?: 0),
                coverName = playlist.coverName,
                modifier = Modifier.stagger(library.playlists.indexOf(playlist) + 1, 16f, 50),
            ) {
                scope.launch {
                    val tracks = library.playlistTracks(playlist)
                    val first = tracks.firstOrNull() ?: return@launch
                    player.applyShuffle(false)
                    player.play(first, tracks)
                }
            }
        }
        if (albums.isNotEmpty()) {
            item(span = full) { Eyebrow("Альбомы", Modifier.padding(top = s(6)), bottom = 0f) }
            items(albums, key = { "a-" + it.first }) { (name, tracks) ->
                CollectionTile(
                    title = name,
                    subtitle = pluralTracks(tracks.size),
                    coverName = tracks.firstOrNull { it.coverName != null }?.coverName,
                    modifier = Modifier.stagger(albums.indexOfFirst { it.first == name } + 1, 16f, 50),
                ) {
                    val first = tracks.firstOrNull() ?: return@CollectionTile
                    player.applyShuffle(false)
                    player.play(first, tracks)
                }
            }
        }
    }
}

@Composable
private fun CollectionTile(title: String, subtitle: String, coverName: String?, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val s = LocalScale.current
    Column(modifier.pressable(0.9f, 0.98f, onClick = onClick), verticalArrangement = Arrangement.spacedBy(s(12))) {
        CoverArt(coverName, Modifier.fillMaxWidth())
        Column(verticalArrangement = Arrangement.spacedBy(s(2))) {
            NText(title, Face.InterMedium, 14f, color = Palette.white, maxLines = 1)
            NText(subtitle, Face.MonoRegular, 11f, color = Palette.dim)
        }
    }
}

@Composable
fun TrackMenuSheet() {
    val s = LocalScale.current
    val graph = LocalGraph.current
    val library = graph.library
    val player = graph.player
    val toasts = graph.toasts
    val track = rememberLast(library.menuTrack)
    SheetScaffold(library.menuTrack != null, { library.menuTrack = null }) {
        if (track == null) return@SheetScaffold
        Column(
            Modifier
                .fillMaxWidth()
                .background(Palette.modal, sheetShape())
                .border(1.dp, Palette.line2, sheetShape())
                .navigationBarsPadding()
                .padding(horizontal = s(12))
                .padding(bottom = s(14)),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(s(4)),
        ) {
            Box(Modifier.padding(top = s(10), bottom = s(6)).width(s(36)).height(s(4)).background(Palette.line2, CapsuleShape))
            Column(Modifier.padding(bottom = s(8)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(s(4))) {
                NText(track.title, Face.UnboundedSemibold, 14f, color = Palette.white, tracking = -0.025f, maxLines = 1)
                NText(track.artist, Face.MonoRegular, 11f, color = Palette.dim, maxLines = 1)
            }
            val entries = listOf(
                MenuEntry("next", "Играть следом", LucideName.ListStart, false),
                MenuEntry("queue", "Добавить в очередь", LucideName.ListEnd, false),
                MenuEntry("playlist", "В плейлист…", LucideName.ListMusic, false),
                MenuEntry("edit", "Редактировать", LucideName.Pencil, false),
                MenuEntry("delete", "Удалить с телефона", LucideName.Trash2, true),
            )
            for (entry in entries) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(s(48))
                        .pressable(0.6f, 0.98f) {
                            when (entry.id) {
                                "next" -> {
                                    player.playNext(track)
                                    toasts.show("Сыграет следующим")
                                }
                                "queue" -> {
                                    player.addToQueue(track)
                                    toasts.show("Добавлено в очередь")
                                }
                                "delete" -> {
                                    player.removeTrack(track.id)
                                    library.delete(track)
                                    toasts.show("Удалено с телефона")
                                }
                                else -> toasts.show("Скоро будет")
                            }
                            library.menuTrack = null
                        }
                        .padding(horizontal = s(14)),
                    horizontalArrangement = Arrangement.spacedBy(s(12)),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(entry.icon, s(18), tint = if (entry.danger) Palette.danger else Palette.muted, stroke = 1.6f)
                    NText(entry.title, Face.InterMedium, 14f, color = if (entry.danger) Palette.danger else Palette.white)
                }
            }
        }
    }
}

private class MenuEntry(val id: String, val title: String, val icon: LucideName, val danger: Boolean)
