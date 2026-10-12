import Foundation
import Observation

@MainActor
final class AppModel {
    let database: AppDatabase
    let library: LibraryStore
    let player: PlayerStore
    let lyrics: LyricsStore
    let toasts: ToastCenter
    let importer: ImportManager
    let site: SiteSession
    let sync: SiteSync
    let updates: UpdateChecker
    let enrichment: EnrichmentService
    let demo: Bool
    private var nowPlaying: NowPlayingController?
    private var engine: PlaybackEngine?

    init(demo: Bool) {
        let db: AppDatabase
        let playback: PlaybackEngine
        let manager: ImportManager
        if demo {
            db = (try? AppDatabase(path: nil)) ?? AppDatabase.open()
            for track in DemoData.tracks() {
                try? db.save(track)
            }
            playback = DemoEngine()
            manager = ImportManager(database: db, catalog: nil)
        } else {
            db = AppDatabase.open()
            playback = SFBEngine()
            manager = ImportManager(database: db)
        }
        let lib = LibraryStore()
        let play = PlayerStore()
        let lyr = LyricsStore()
        let toast = ToastCenter()
        let siteSession = SiteSession()
        let updateChecker = UpdateChecker()
        self.demo = demo
        database = db
        importer = manager
        engine = playback
        library = lib
        player = play
        lyrics = lyr
        toasts = toast
        site = siteSession
        sync = SiteSync(database: db, library: lib)
        updates = updateChecker
        let enrich = EnrichmentService(database: db, lyrics: lyr)
        enrichment = enrich

        lyr.database = db
        play.attach(playback)
        lib.attach(db)
        nowPlaying = NowPlayingController(player: play)
        play.onTrackStarted = { track in
            lib.markPlayed(track.id)
            Task { await lyr.ensure(track) }
        }
        if let real = playback as? SFBEngine {
            real.onError = { message in
                toast.show("Не удалось воспроизвести: \(message)")
            }
        }
        manager.onTrackRemoved = { id in
            play.queue.removeAll { $0.id == id }
        }
        if !demo {
            manager.onTrackAdded = { track in
                enrich.enqueue(track)
            }
        }
        if !demo {
            Task {
                await siteSession.restore()
                await updateChecker.check()
            }
        }
    }
}
