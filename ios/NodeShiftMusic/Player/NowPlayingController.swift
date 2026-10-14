import Foundation
import MediaPlayer
import Observation
import UIKit

@MainActor
final class NowPlayingController {
    private let player: PlayerStore
    private var artworkCache: [String: MPMediaItemArtwork] = [:]
    private var fetching: Set<String> = []

    init(player: PlayerStore) {
        self.player = player
        setupRemoteCommands()
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = player.current?.id
            _ = player.current?.motionName
            _ = player.isPlaying
            _ = player.duration
            _ = player.seekToken
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observe()
            }
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.togglePlay() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.player.seek(to: position) }
            return .success
        }
    }

    private func artwork(for track: TrackRecord) -> MPMediaItemArtwork? {
        guard let name = track.coverName else { return nil }
        if let cached = artworkCache[name] {
            return cached
        }
        if CoverSource.isRemote(name) {
            fetchRemoteArtwork(name)
            return nil
        }
        let url = AppPaths.coverURL(name)
        guard let image = CoverImageLoader.downsample(url, maxPixel: 1000) else { return nil }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        artworkCache[name] = artwork
        if artworkCache.count > 20 {
            artworkCache.removeAll()
            artworkCache[name] = artwork
        }
        return artwork
    }

    private func fetchRemoteArtwork(_ name: String) {
        guard !fetching.contains(name) else { return }
        fetching.insert(name)
        Task { [weak self] in
            let image = await CoverImageLoader.shared.image(url: CoverSource.url(for: name, maxPixel: 1000), maxPixel: 1000)
            guard let self else { return }
            self.fetching.remove(name)
            guard let image else { return }
            self.artworkCache[name] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.refresh()
        }
    }

    func refresh() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = player.current else {
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.time(at: Date()),
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let album = track.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let artwork = artwork(for: track) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        if #available(iOS 26.0, *) {
            AnimatedArtwork.apply(to: &info, track: track)
        }
        center.nowPlayingInfo = info
    }
}
