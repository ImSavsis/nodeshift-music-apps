import Foundation
import Observation

@MainActor
final class PresenceReporter {
    private weak var player: PlayerStore?
    private weak var site: SiteSession?
    private var heartbeat: Timer?
    private var sentTrack: String?
    private var artCache: [String: String]

    init() {
        artCache = UserDefaults.standard.dictionary(forKey: "nsm_presence_art") as? [String: String] ?? [:]
    }

    func attach(player: PlayerStore, site: SiteSession) {
        self.player = player
        self.site = site
        observe()
    }

    private func observe() {
        guard let player else { return }
        withObservationTracking {
            _ = player.current?.id
            _ = player.isPlaying
            _ = player.seekToken
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.changed()
                self?.observe()
            }
        }
    }

    private func changed() {
        guard let player, site?.isLoggedIn == true, SoundSettings.shared.discordPresence else {
            stopHeartbeat()
            return
        }
        guard player.current != nil else {
            stopHeartbeat()
            if sentTrack != nil {
                sentTrack = nil
                Task { await SiteAPI.shared.publishPresence(["stop": true]) }
            }
            return
        }
        Task { await send() }
        if player.isPlaying {
            startHeartbeat()
        } else {
            stopHeartbeat()
        }
    }

    private func startHeartbeat() {
        guard heartbeat == nil else { return }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.send()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    private func stopHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = nil
    }

    private func send() async {
        guard let player, let track = player.current, SoundSettings.shared.discordPresence else { return }
        sentTrack = track.id
        let cover = await coverURL(for: track)
        var body: [String: Any] = [
            "device": BumpSession.deviceID,
            "platform": "ios",
            "playing": player.isPlaying,
            "title": track.title,
            "artist": track.artist,
            "album": track.album ?? "",
            "position_ms": Int(player.time(at: Date()) * 1000),
            "duration_ms": Int(player.duration * 1000),
        ]
        if let cover {
            body["cover"] = cover
        }
        if let siteID = track.siteId {
            body["site_id"] = siteID
        }
        await SiteAPI.shared.publishPresence(body)
    }

    private func coverURL(for track: TrackRecord) async -> String? {
        guard let name = track.coverName else { return nil }
        if CoverSource.isRemote(name) {
            return CoverSource.fullURL(for: name).absoluteString
        }
        if name.hasPrefix("site-") {
            return SiteAPI.shared.coverURL(String(name.dropFirst(5))).absoluteString
        }
        if let known = artCache[name] {
            return known
        }
        guard let data = try? Data(contentsOf: AppPaths.coverURL(name)) else { return nil }
        var jpeg = ImportManager.normalizedJPEG(data, maxSide: 600)
        if let current = jpeg, current.count > 580_000 {
            jpeg = ImportManager.normalizedJPEG(data, maxSide: 360)
        }
        guard let jpeg, jpeg.count <= 600_000, let url = await SiteAPI.shared.uploadPresenceArt(jpeg) else { return nil }
        artCache[name] = url
        UserDefaults.standard.set(artCache, forKey: "nsm_presence_art")
        return url
    }
}
