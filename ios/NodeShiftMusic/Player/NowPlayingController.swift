import Foundation
import MediaPlayer
import Observation
import UIKit

@MainActor
final class NowPlayingController {
    private let player: PlayerStore
    private var artworkCache: [String: MPMediaItemArtwork] = [:]

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
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]

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
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.player.seek(to: self.player.time(at: Date()) + 15)
            }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.player.seek(to: self.player.time(at: Date()) - 15)
            }
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
