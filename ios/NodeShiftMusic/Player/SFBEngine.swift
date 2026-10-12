import AVFoundation
import SFBAudioEngine

@MainActor
final class SFBEngine: NSObject, PlaybackEngine {
    private let player = AudioPlayer()
    var onEnded: (() -> Void)?
    var onError: ((String) -> Void)?
    private var sessionReady = false

    override init() {
        super.init()
        player.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    var currentTime: Double {
        player.currentTime ?? 0
    }

    var totalTime: Double {
        player.totalTime ?? 0
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        if !sessionReady {
            try? session.setCategory(.playback, mode: .default, options: [])
            sessionReady = true
        }
        try? session.setActive(true)
    }

    func load(_ track: TrackRecord, autoplay: Bool) {
        activateSession()
        do {
            try player.play(track.fileURL)
            if !autoplay {
                _ = player.pause()
            }
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func play() {
        activateSession()
        if player.isPaused {
            _ = player.resume()
        } else if !player.isPlaying {
            try? player.play()
        }
    }

    func pause() {
        _ = player.pause()
    }

    func seek(to seconds: Double) {
        _ = player.seek(time: seconds)
    }

    func stop() {
        player.stop()
    }

    @objc private func routeChanged(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        Task { @MainActor [weak self] in
            self?.pause()
            self?.onRouteLost?()
        }
    }

    var onRouteLost: (() -> Void)?
}

extension SFBEngine: AudioPlayer.Delegate {
    nonisolated func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        Task { @MainActor [weak self] in
            self?.onEnded?()
        }
    }

    nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.onError?(message)
        }
    }
}
