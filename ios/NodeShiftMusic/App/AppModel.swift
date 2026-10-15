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
    let catalog: CatalogStore
    let room: RoomStore
    private let presence = PresenceReporter()
    let demo: Bool
    private var nowPlaying: NowPlayingController?
    private var audioWatcher: AudioSessionWatcher?
    private var engine: PlaybackEngine?

    static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var launchDemo: Bool {
        ProcessInfo.processInfo.arguments.contains("-nsm-demo") || isTestHost
    }

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
        let cat = CatalogStore()
        catalog = cat
        let roomStore = RoomStore()
        room = roomStore
        roomStore.attach(player: play, catalog: cat, toasts: toast)
        presence.attach(player: play, site: siteSession)
        let reporter = presence
        siteSession.onWillLogout = {
            reporter.stopNow()
        }
        cat.attach(library: lib, site: siteSession, toasts: toast)
        siteSession.onSessionChanged = {
            Task { await cat.refreshLikes() }
        }

        lyr.database = db
        play.attach(playback)
        audioWatcher = AudioSessionWatcher(player: play)
        lib.attach(db)
        nowPlaying = NowPlayingController(player: play)
        play.onTrackStarted = { track in
            if track.isRemote {
                if let siteID = track.siteId {
                    Task { await SiteAPI.shared.registerPlay(siteID) }
                }
            } else {
                lib.markPlayed(track.id)
            }
            Task { await lyr.ensure(track) }
        }
        if let real = playback as? SFBEngine {
            real.onError = { message in
                toast.show("Не удалось воспроизвести: \(message)")
            }
            real.onRouteLost = { [weak play] in
                play?.pause()
            }
        }
        if !demo {
            let remote = RemoteEngine()
            remote.onError = { message in
                toast.show("Не удалось воспроизвести: \(message)")
            }
            remote.onRouteLost = { [weak play] in
                play?.pause()
            }
            play.attachRemote(remote)
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
            DiscordLink.shared.restore()
            Task {
                await siteSession.restore()
                await updateChecker.check()
            }
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await enrich.enrichLibrary(force: false)
                await MotionStore.shared.trimCache()
            }
        }
    }
}
