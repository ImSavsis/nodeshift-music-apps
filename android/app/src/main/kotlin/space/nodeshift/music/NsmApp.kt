package space.nodeshift.music

import android.app.Application
import android.util.Log
import androidx.compose.runtime.staticCompositionLocalOf
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import space.nodeshift.music.data.AppDatabase
import space.nodeshift.music.data.AppPaths
import space.nodeshift.music.data.LibraryStore
import space.nodeshift.music.data.Prefs
import space.nodeshift.music.design.Typefaces
import space.nodeshift.music.imports.EnrichmentService
import space.nodeshift.music.imports.ImportManager
import space.nodeshift.music.lyrics.LyricsStore
import space.nodeshift.music.player.PlayerStore
import space.nodeshift.music.site.CatalogStore
import space.nodeshift.music.site.SiteApi
import space.nodeshift.music.site.SiteSession
import space.nodeshift.music.site.SiteSync
import space.nodeshift.music.site.UpdateChecker
import space.nodeshift.music.ui.ToastCenter

class AppGraph(app: Application) {
    val scope = CoroutineScope(
        SupervisorJob() + Dispatchers.Main.immediate + CoroutineExceptionHandler { _, error -> Log.e("NsmApp", "uncaught", error) },
    )
    val database = AppDatabase(app)
    val library = LibraryStore(database, scope)
    val player = PlayerStore(app, library, scope)
    val lyrics = LyricsStore(database)
    val toasts = ToastCenter(scope)
    val importer = ImportManager(app, database, scope)
    val site = SiteSession()
    val sync = SiteSync(database, library)
    val updates = UpdateChecker(app)
    val enrichment = EnrichmentService(database, lyrics, scope)
    val catalog = CatalogStore(library, site, toasts, scope)
    val room = space.nodeshift.music.site.RoomStore(player, catalog, toasts, scope)
    val bump = space.nodeshift.music.site.BumpSession(app, scope)
    val presence = space.nodeshift.music.site.PresenceReporter(player, site, sync, scope)

    init {
        player.onTrackStarted = { track ->
            val siteId = track.siteId
            if (track.isRemote && siteId != null) {
                scope.launch(Dispatchers.IO) { SiteApi.registerPlay(siteId) }
            } else {
                library.markPlayed(track.id)
            }
            scope.launch { lyrics.ensure(track) }
        }
        site.onSessionChanged = { scope.launch { catalog.refreshLikes() } }
        site.beforeLogout = { presence.retireNow() }
        SiteApi.onExpired = { scope.launch { site.expire() } }
        player.onError = { message -> toasts.show("Не удалось воспроизвести: $message") }
        importer.onTrackRemoved = { id -> player.removeTrack(id) }
        importer.onTrackAdded = { track -> enrichment.enqueue(track) }
        player.connect()
        presence.start()
        scope.launch { site.restore() }
        scope.launch { updates.check() }
    }
}

val LocalGraph = staticCompositionLocalOf<AppGraph> { error("graph") }

class NsmApp : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        AppPaths.init(this)
        Prefs.init(this)
        Typefaces.init(assets)
        SiteApi.load()
        graph = AppGraph(this)
    }
}
