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

    private func source(for track: TrackRecord, compact: Bool) -> URL? {
        if track.isLocked {
            guard let site = track.siteId else { return nil }
            let kind = track.fileName.hasSuffix(".nlac") ? "lossless" : "lossy"
            return LockedMediaServer.shared.url("file/\(site)/\(kind)/\(track.fileName)")
        }
        if !track.isRemote {
            return track.fileURL
        }
        if compact {
            return track.streamURL ?? track.losslessURL
        }
        if let site = track.siteId {
            let original = SoundSettings.shared.wantsLossless() && AudioFormats.lossless.contains(track.format.lowercased())
            if let protected = LockedMediaServer.shared.url("site/\(site)/\(original ? "lossless" : "lossy")") {
                return protected
            }
        }
        if SoundSettings.shared.wantsLossless(), let original = track.losslessURL {
            return original
        }
        return track.streamURL ?? track.losslessURL
    }

    func load(_ track: TrackRecord, autoplay: Bool) {
        open(track, autoplay: autoplay, compact: false)
    }

    private func open(_ track: TrackRecord, autoplay: Bool, compact: Bool) {
        guard let url = source(for: track, compact: compact) else {
            onError?("у трека нет адреса потока")
            return
        }
        activateSession()
        detach()
        let item = AVPlayerItem(url: url)
        item.allowedAudioSpatializationFormats = SoundSettings.shared.atmosMode == .off ? [] : .monoStereoAndMultichannel
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
                guard let self else { return }
                if track.isRemote, !compact, let fallback = track.streamURL, fallback != url {
                    self.open(track, autoplay: true, compact: true)
                } else {
                    self.onError?(message)
                }
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
