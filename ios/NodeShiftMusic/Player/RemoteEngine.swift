import AVFoundation

@MainActor
final class RemoteEngine: NSObject, PlaybackEngine {
    private let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var sessionReady = false
    var onEnded: (() -> Void)?
    var onError: ((String) -> Void)?
    var onRouteLost: (() -> Void)?

    override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    var currentTime: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }

    var totalTime: Double {
        guard let item = player.currentItem else { return 0 }
        let seconds = item.duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        if !sessionReady {
            try? session.setCategory(.playback, mode: .default, options: [])
            sessionReady = true
        }
        try? session.setActive(true)
    }

    private func detach() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
    }

    func load(_ track: TrackRecord, autoplay: Bool) {
        guard let url = track.streamURL else {
            onError?("у трека нет адреса потока")
            return
        }
        activateSession()
        detach()
        let item = AVPlayerItem(url: url)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onEnded?()
            }
        }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            guard observed.status == .failed else { return }
            let message = observed.error?.localizedDescription ?? "ошибка потока"
            Task { @MainActor in
                self?.onError?(message)
            }
        }
        player.replaceCurrentItem(with: item)
        if autoplay {
            player.play()
        }
    }

    func play() {
        activateSession()
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double) {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player.pause()
        detach()
        player.replaceCurrentItem(with: nil)
    }

    @objc private func routeChanged(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        Task { @MainActor [weak self] in
            self?.pause()
            self?.onRouteLost?()
        }
    }
}
