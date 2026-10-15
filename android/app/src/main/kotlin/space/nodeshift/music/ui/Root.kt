package space.nodeshift.music.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import space.nodeshift.music.LocalGraph
import space.nodeshift.music.MainActivity
import space.nodeshift.music.data.LibraryViewMode
import space.nodeshift.music.design.FlowField
import space.nodeshift.music.design.LocalReduceMotion
import space.nodeshift.music.design.LocalScale
import space.nodeshift.music.design.Motion
import space.nodeshift.music.design.MotionClockHost
import space.nodeshift.music.design.Palette
import space.nodeshift.music.design.Scale
import space.nodeshift.music.design.animationsDisabled

@Composable
fun NsmRoot(activity: MainActivity) {
    val graph = LocalGraph.current
    val library = graph.library
    val player = graph.player
    val site = graph.site
    val context = LocalContext.current
    val density = LocalDensity.current
    val configuration = LocalConfiguration.current
    val scale = remember(configuration.screenWidthDp) { Scale.forWidth(configuration.screenWidthDp.toFloat()) }
    val reduce = remember(configuration) { animationsDisabled(context) }
    var tab by rememberSaveable { mutableStateOf(AppTab.Tracks) }
    var showMore by remember { mutableStateOf(false) }
    var showStorage by remember { mutableStateOf(false) }
    var showTogether by remember { mutableStateOf(false) }
    var chromeHeight by remember { mutableStateOf(0.dp) }
    val scope = rememberCoroutineScope()

    val demoExtras = activity.intent
    var demoHandled by remember { mutableStateOf(false) }
    LaunchedEffect(library.tracks.size) {
        if (demoHandled || !demoExtras.getBooleanExtra("nsm_demo", false) || library.tracks.isEmpty()) return@LaunchedEffect
        demoHandled = true
        delay(500)
        val sorted = library.tracks.sortedBy { it.id }
        when (val route = demoExtras.getStringExtra("nsm_route")) {
            "playlists" -> tab = AppTab.Playlists
            "favorites" -> tab = AppTab.Favorites
            "import" -> tab = AppTab.Importer
            "list" -> library.changeViewMode(LibraryViewMode.List)
            "more" -> showMore = true
            "storage" -> showStorage = true
            "player", "lyrics", "queue" -> {
                val first = sorted.firstOrNull()
                if (first != null) {
                    player.play(first, sorted)
                    player.isFullPlayerOpen = true
                    player.isQueueOpen = route == "queue"
                }
            }
        }
        if (demoExtras.getBooleanExtra("nsm_playing", false)) {
            sorted.getOrNull(2)?.let { player.play(it, sorted) }
        }
        val seek = demoExtras.getDoubleExtra("nsm_seek", -1.0)
        if (seek >= 0) {
            delay(900)
            player.seek(seek)
        }
    }

    val notifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    BackHandler(
        enabled = showTogether || player.isQueueOpen || library.menuTrack != null || player.isFullPlayerOpen || showStorage || showMore || tab != AppTab.Tracks,
    ) {
        when {
            showTogether -> showTogether = false
            library.menuTrack != null -> library.menuTrack = null
            player.isQueueOpen -> player.isQueueOpen = false
            player.isFullPlayerOpen -> player.isFullPlayerOpen = false
            showStorage -> showStorage = false
            showMore -> showMore = false
            else -> tab = AppTab.Tracks
        }
    }

    CompositionLocalProvider(
        LocalScale provides scale,
        LocalReduceMotion provides reduce,
        LocalBottomInset provides chromeHeight,
        LocalOpenTab provides { target: AppTab -> tab = target },
        LocalOpenStorage provides { showStorage = true },
    ) {
        MotionClockHost(!reduce)
        Box(Modifier.fillMaxSize().background(Palette.bg)) {
            FlowField()
            AnimatedContent(
                targetState = tab,
                transitionSpec = {
                    (fadeIn(Motion.page()) + slideInVertically(Motion.page()) { with(density) { 12.dp.roundToPx() } })
                        .togetherWith(fadeOut(Motion.page()))
                },
                label = "page",
            ) { target ->
                when (target) {
                    AppTab.Tracks -> LibraryScreen()
                    AppTab.Playlists -> PlaylistsScreen()
                    AppTab.Favorites -> FavoritesScreen()
                    AppTab.Importer -> ImportScreen()
                }
            }
            Column(
                Modifier
                    .align(Alignment.BottomCenter)
                    .onSizeChanged { chromeHeight = with(density) { it.height.toDp() } },
            ) {
                MiniPlayer()
                if (player.current != null) Box(Modifier.height(scale(8)))
                BottomBar(tab, showMore, onSelect = { tab = it; showMore = false }, onMore = { showMore = !showMore })
            }
            val user = site.user
            MoreSheet(
                visible = showMore,
                loggedIn = site.isLoggedIn,
                loginTitle = if (site.isLoggedIn) "Выйти (${user?.handle?.let { "@$it" } ?: "аккаунт"})" else "Войти",
                versionLine = "Версия ${graph.updates.currentVersion} (${graph.updates.currentBuild})",
                onDismiss = { showMore = false },
            ) { item ->
                when (item) {
                    MoreItem.Storage -> showStorage = true
                    MoreItem.Together -> showTogether = true
                    MoreItem.Login -> scope.launch { if (site.isLoggedIn) site.logout() else site.login(activity) }
                    else -> graph.toasts.show("${item.title} скоро будет")
                }
            }
            AnimatedVisibility(
                showStorage,
                enter = slideInHorizontally(Motion.expoOut(320)) { it },
                exit = slideOutHorizontally(Motion.expoOut(280)) { it },
            ) { StorageScreen { showStorage = false } }
            AnimatedVisibility(
                player.isFullPlayerOpen,
                enter = slideInVertically(Motion.expoOut(380)) { it } + fadeIn(Motion.fade(260)),
                exit = slideOutVertically(Motion.expoOut(320)) { it } + fadeOut(Motion.fade(220)),
            ) { FullPlayerScreen() }
            QueueSheet()
            TrackMenuSheet()
            TogetherSheet(showTogether) { showTogether = false }
            ToastHost()
        }
    }
}
