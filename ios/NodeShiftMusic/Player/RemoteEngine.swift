import AVFoundation
import NSMCore

@MainActor
private final class MixDeck {
    let player = AVPlayer()
    var track: TrackRecord?
    var endObserver: NSObjectProtocol?
    var statusObservation: NSKeyValueObservation?
    var filter: DeckFilter?
    var loadToken = 0
    var isReady = false
    var compact = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
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

    func detach() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
    }

    func clear() {
        player.pause()
        detach()
        filter?.bypass()
        filter = nil
        player.volume = 0
        player.defaultRate = 1
        player.replaceCurrentItem(with: nil)
        track = nil
        isReady = false
        compact = false
        loadToken += 1
    }

    func setRate(_ rate: Double, playing: Bool) {
        let clamped = Float(max(0.5, min(2.0, rate)))
        player.defaultRate = clamped
        if playing, player.rate > 0, abs(player.rate - clamped) > 0.0005 {
            player.rate = clamped
        }
    }

    func attachFilter(token: Int) {
        guard filter == nil, let item = player.currentItem, !(track?.isDolbyAtmos ?? false) else { return }
        let deckFilter = DeckFilter()
        filter = deckFilter
        Task { @MainActor [weak self] in
            guard let self, self.loadToken == token, let current = self.player.currentItem, current === item else { return }
            guard let audioTrack = try? await current.asset.loadTracks(withMediaType: .audio).first else { return }
            guard self.loadToken == token, self.player.currentItem === current else { return }
            if let mix = deckFilter.makeAudioMix(for: audioTrack) {
                current.audioMix = mix
            }
        }
    }
}

@MainActor
final class RemoteEngine: NSObject, MixCapableEngine {
    private var active = MixDeck()
    private var idle = MixDeck()
    private var sessionReady = false
    private var mixing = false
    private var prepared = false
    private var preparedIndex = -1
    private var blockedIndex = -1
    private var plan: MixPlan?
    private var incomingTrack: TrackRecord?
    private var incomingIndex = -1
    private var armed: (plan: MixPlan, track: TrackRecord, index: Int)?
    private var fadeSeconds = 0.0
    private var wallStart = 0.0
    private var pausedFor = 0.0
    private var pausedAt = 0.0
    private var pendingOffset = 0.0
    private var wantSide = false
    private var progress = 0.0
    private var hardFixed = false
    private var finishing = false
    private var playing = false
    private var sideToken = 0
    private var rateRamp: (from: Double, start: Double)?
    private var mixTimer: Timer?

    var onEnded: (() -> Void)?
    var onError: ((String) -> Void)?
    var onRouteLost: (() -> Void)?
    var onMixStarted: ((TrackRecord, Int) -> Void)?
    var onMixProgress: ((Double) -> Void)?
    var onMixHandover: ((Int, Double) -> Void)?
    var onMixCancel: (() -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    var currentTime: Double {
        active.currentTime
    }

    var totalTime: Double {
        active.totalTime
    }

    var isMixing: Bool {
        mixing
    }

    func isPrepared(for index: Int) -> Bool {
        prepared && preparedIndex == index && idle.track != nil
    }

    func isBlocked(index: Int) -> Bool {
        blockedIndex == index
    }

    func clearBlocked() {
        blockedIndex = -1
    }

    private func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        if !sessionReady {
            try? session.setCategory(.playback, mode: .default, options: [])
            sessionReady = true
        }
        try? session.setActive(true)
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
        cancelMix()
        blockedIndex = -1
        playing = autoplay
        open(deck: active, track: track, autoplay: autoplay, compact: false, isSide: false)
    }

    private func open(deck: MixDeck, track: TrackRecord, autoplay: Bool, compact: Bool, isSide: Bool) {
        guard let url = source(for: track, compact: compact) else {
            if isSide {
                failSide()
            } else {
                onError?("у трека нет адреса потока")
            }
            return
        }
        activateSession()
        deck.detach()
        deck.filter?.bypass()
        deck.filter = nil
        deck.loadToken += 1
        let token = deck.loadToken
        deck.track = track
        deck.compact = compact
        deck.isReady = false

        let item = AVPlayerItem(url: url)
        item.allowedAudioSpatializationFormats = SoundSettings.shared.atmosMode == .off ? [] : .monoStereoAndMultichannel
        item.audioTimePitchAlgorithm = track.isDolbyAtmos ? .timeDomain : .spectral
        if isSide {
            item.preferredForwardBufferDuration = 15
        }

        deck.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak deck] _ in
            Task { @MainActor in
                guard let self, let deck, deck.loadToken == token else { return }
                self.handleDeckEnded(deck)
            }
        }

        deck.statusObservation = item.observe(\.status, options: [.new]) { [weak self, weak deck] observed, _ in
            let status = observed.status
            let message = observed.error?.localizedDescription ?? "ошибка потока"
            Task { @MainActor in
                guard let self, let deck, deck.loadToken == token else { return }
                if status == .readyToPlay {
                    self.handleDeckReady(deck, token: token)
                } else if status == .failed {
                    if track.isRemote, !compact, let fallback = track.streamURL, fallback != url {
                        self.open(deck: deck, track: track, autoplay: isSide ? false : self.playing, compact: true, isSide: isSide)
                    } else if deck === self.idle {
                        self.failSide()
                    } else {
                        self.onError?(message)
                    }
                }
            }
        }

        deck.player.volume = isSide ? 0 : 1
        deck.player.defaultRate = isSide ? Float(plan?.inRate ?? 1.0) : 1.0
        deck.player.replaceCurrentItem(with: item)
        if !isSide && autoplay {
            deck.player.play()
        } else {
            deck.player.pause()
        }
    }

    private func handleDeckReady(_ deck: MixDeck, token: Int) {
        deck.attachFilter(token: token)
        if deck === idle {
            let offset = max(0, pendingOffset)
            let target = CMTime(seconds: offset, preferredTimescale: 600)
            deck.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak deck] _ in
                Task { @MainActor in
                    guard let self, let deck, deck === self.idle, deck.loadToken == token else { return }
                    deck.isReady = true
                    if self.wantSide && self.mixing {
                        self.wantSide = false
                        self.beginFade()
                        if self.playing {
                            self.startIdlePlayback()
                        }
                    }
                }
            }
        } else {
            deck.isReady = true
        }
    }

    private func handleDeckEnded(_ deck: MixDeck) {
        if deck === active {
            if mixing {
                finishMix()
            } else {
                onEnded?()
            }
        } else if deck === idle && mixing {
            finishMix()
        }
    }

    func prepareMix(track: TrackRecord, index: Int, offset: Double) {
        guard blockedIndex != index else { return }
        if prepared && preparedIndex == index && idle.track?.id == track.id {
            pendingOffset = offset
            return
        }
        sideToken += 1
        prepared = true
        preparedIndex = index
        pendingOffset = offset
        wantSide = false
        open(deck: idle, track: track, autoplay: false, compact: false, isSide: true)
    }

    func armMix(plan: MixPlan, track: TrackRecord, index: Int) {
        guard !mixing, plan.kind != .none, blockedIndex != index else { return }
        armed = (plan, track, index)
        ensureTimer()
    }

    func startMix(plan: MixPlan, track: TrackRecord, index: Int) {
        guard !mixing, plan.kind != .none else { return }
        armed = nil
        if !isPrepared(for: index) || idle.track?.id != track.id {
            prepareMix(track: track, index: index, offset: plan.inOffset)
        }
        self.plan = plan
        incomingTrack = track
        incomingIndex = index
        mixing = true
        finishing = false
        progress = 0
        hardFixed = false
        pausedAt = 0
        pausedFor = 0
        pendingOffset = plan.inOffset
        rateRamp = nil
        idle.player.defaultRate = Float(max(0.5, min(2.0, plan.inRate)))
        active.player.defaultRate = 1.0
        render(AutoMix.curve(kind: plan.kind, progress: 0))
        onMixStarted?(track, index)

        if idle.isReady {
            if abs(idle.currentTime - plan.inOffset) > 0.03 {
                let token = sideToken
                let target = CMTime(seconds: max(0, plan.inOffset), preferredTimescale: 600)
                wantSide = true
                wallStart = 0
                idle.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.mixing, self.sideToken == token else { return }
                        self.wantSide = false
                        self.beginFade()
                        if self.playing {
                            self.startIdlePlayback()
                        }
                    }
                }
            } else {
                wantSide = false
                beginFade()
                if playing {
                    startIdlePlayback()
                }
            }
        } else {
            wantSide = true
            wallStart = 0
        }
        ensureTimer()
    }

    private func startIdlePlayback() {
        guard let plan else { return }
        let rate = Float(max(0.5, min(2.0, plan.inRate)))
        idle.player.defaultRate = rate
        idle.player.playImmediately(atRate: rate)
    }

    private func beginFade() {
        guard let plan else { return }
        let late = max(0.0, active.currentTime - plan.outStart)
        fadeSeconds = max(2.0, plan.overlap - late)
        wallStart = now()
        pausedFor = 0
        pausedAt = playing ? 0 : wallStart
    }

    private func render(_ curve: MixCurve) {
        active.player.volume = Float(min(1, max(0, curve.outGain)))
        active.filter?.update(active: true, hz: Float(curve.outHz), bassDb: Float(curve.outBass))
        idle.player.volume = Float(min(1, max(0, curve.inGain)))
        idle.filter?.update(active: true, hz: 18000, bassDb: Float(curve.inBass))
    }

    private func finishMix() {
        guard !finishing, mixing else { return }
        finishing = true
        let index = incomingIndex
        let time = idle.currentTime
        let rate = idle.player.rate > 0 ? Double(idle.player.rate) : Double(idle.player.defaultRate)
        mixing = false
        plan = nil
        incomingTrack = nil
        armed = nil
        prepared = false
        preparedIndex = -1
        wantSide = false
        sideToken += 1
        progress = 1

        active.clear()
        let previous = active
        active = idle
        idle = previous
        active.player.volume = 1
        active.filter?.bypass()
        idle.player.volume = 0

        if abs(rate - 1.0) > 0.008 {
            rateRamp = (from: rate, start: now())
        } else {
            active.setRate(1.0, playing: playing)
        }
        finishing = false
        onMixHandover?(index, time)
        if rateRamp != nil {
            ensureTimer()
        } else {
            stopTimer()
        }
    }

    private func failSide() {
        blockedIndex = mixing ? incomingIndex : preparedIndex
        cancelMix()
    }

    func cancelPrepared() {
        guard !mixing else { return }
        armed = nil
        if prepared {
            prepared = false
            preparedIndex = -1
            wantSide = false
            sideToken += 1
            idle.clear()
        }
        if rateRamp == nil {
            stopTimer()
        }
    }

    func cancelMix() {
        let wasMixing = mixing
        mixing = false
        plan = nil
        incomingTrack = nil
        incomingIndex = -1
        armed = nil
        prepared = false
        preparedIndex = -1
        wantSide = false
        sideToken += 1
        rateRamp = nil
        pausedAt = 0
        pausedFor = 0
        wallStart = 0
        progress = 0
        active.setRate(1.0, playing: playing)
        active.player.volume = 1
        active.filter?.bypass()
        idle.clear()
        stopTimer()
        if wasMixing {
            onMixCancel?()
        }
    }

    func play() {
        activateSession()
        playing = true
        if pausedAt > 0 {
            pausedFor += now() - pausedAt
            pausedAt = 0
        }
        if mixing && wallStart == 0 && idle.isReady && !wantSide {
            beginFade()
        }
        active.player.play()
        if mixing && idle.isReady && !wantSide {
            idle.player.play()
        }
        if mixing || rateRamp != nil || armed != nil {
            ensureTimer()
        }
    }

    func pause() {
        playing = false
        if mixing && wallStart > 0 && pausedAt == 0 {
            pausedAt = now()
        }
        active.player.pause()
        idle.player.pause()
    }

    func seek(to seconds: Double) {
        cancelMix()
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        active.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        playing = false
        cancelMix()
        active.clear()
    }

    private func ensureTimer() {
        guard mixTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.frame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mixTimer = timer
    }

    private func stopTimer() {
        mixTimer?.invalidate()
        mixTimer = nil
    }

    private func frame() {
        if let pendingArm = armed, !mixing {
            if playing && active.currentTime >= pendingArm.plan.outStart {
                armed = nil
                startMix(plan: pendingArm.plan, track: pendingArm.track, index: pendingArm.index)
            }
        }
        if let ramp = rateRamp {
            let t = (now() - ramp.start) / 5.0
            if t >= 1.0 {
                active.setRate(1.0, playing: playing)
                rateRamp = nil
            } else {
                let eased = t * t * (3.0 - 2.0 * t)
                active.setRate(ramp.from + (1.0 - ramp.from) * eased, playing: playing)
            }
        }
        if mixing, let plan, plan.kind != .none, wallStart > 0, pausedAt == 0 {
            let elapsed = now() - wallStart - pausedFor
            let nextProgress = min(1.0, max(0.0, elapsed / fadeSeconds))
            progress = nextProgress
            render(AutoMix.curve(kind: plan.kind, progress: nextProgress))
            onMixProgress?(nextProgress)
            lock(progress: nextProgress)
            if nextProgress >= 1.0 {
                finishMix()
            }
        }
        if !mixing && rateRamp == nil && armed == nil {
            stopTimer()
        }
    }

    private func lock(progress: Double) {
        guard let plan, let sync = plan.sync, playing else { return }
        guard idle.isReady, idle.player.timeControlStatus == .playing, idle.player.rate > 0 else { return }
        let result = AutoMix.phaseLock(
            progress: progress,
            outTime: active.currentTime,
            inTime: idle.currentTime,
            outRateTarget: plan.outRate,
            sync: sync,
            hardFixed: hardFixed
        )
        active.setRate(result.outRate, playing: playing)
        if result.markFixed {
            hardFixed = true
        }
        if let seekTo = result.seekTo {
            let target = CMTime(seconds: seekTo, preferredTimescale: 600)
            idle.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        idle.setRate(result.inRate, playing: playing)
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
