import Foundation
import NSMCore
import Observation

enum RepeatMode: String, Sendable {
    case off
    case all
    case one

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

struct ActiveMix: Equatable, Sendable {
    var track: TrackRecord
    var index: Int
    var progress: Double
}

@MainActor
protocol PlaybackEngine: AnyObject {
    var currentTime: Double { get }
    var totalTime: Double { get }
    var onEnded: (() -> Void)? { get set }
    func load(_ track: TrackRecord, autoplay: Bool)
    func play()
    func pause()
    func seek(to seconds: Double)
    func stop()
}

@MainActor
protocol MixCapableEngine: PlaybackEngine {
    var isMixing: Bool { get }
    var onMixStarted: ((TrackRecord, Int) -> Void)? { get set }
    var onMixProgress: ((Double) -> Void)? { get set }
    var onMixHandover: ((Int, Double) -> Void)? { get set }
    var onMixCancel: (() -> Void)? { get set }
    func isPrepared(for index: Int) -> Bool
    func isBlocked(index: Int) -> Bool
    func clearBlocked()
    func prepareMix(track: TrackRecord, index: Int, offset: Double)
    func armMix(plan: MixPlan, track: TrackRecord, index: Int)
    func startMix(plan: MixPlan, track: TrackRecord, index: Int)
    func cancelMix()
    func cancelPrepared()
}

@MainActor
@Observable
final class PlayerStore {
    var queue: [TrackRecord] = []
    var currentIndex: Int?
    var isPlaying = false
    var position: Double = 0
    var duration: Double = 0
    var shuffle = false
    var repeatMode: RepeatMode = .off
    var mix: ActiveMix?
    var isFullPlayerOpen = false
    var isQueueOpen = false
    var syncDate = Date()
    var seekToken = 0

    @ObservationIgnored private var engine: PlaybackEngine?
    @ObservationIgnored private var localEngine: PlaybackEngine?
    @ObservationIgnored private var remoteEngine: PlaybackEngine?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var history: [Int] = []
    @ObservationIgnored private var nextPin: (fromId: String, toId: String)?
    @ObservationIgnored var onTrackStarted: ((TrackRecord) -> Void)?
    @ObservationIgnored var endedHandler: (() -> Bool)?

    var autoMix: Bool {
        SoundSettings.shared.autoMix
    }

    var engineTime: Double {
        engine?.currentTime ?? position
    }

    var engineDuration: Double {
        engine?.totalTime ?? 0
    }

    var current: TrackRecord? {
        guard let index = currentIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    var upcomingCount: Int {
        guard let index = currentIndex else { return queue.count }
        return max(0, queue.count - index - 1)
    }

    func attach(_ engine: PlaybackEngine) {
        localEngine = engine
        self.engine = engine
        engine.onEnded = { [weak self] in
            self?.handleEnded()
        }
    }

    func attachRemote(_ engine: PlaybackEngine) {
        remoteEngine = engine
        engine.onEnded = { [weak self] in
            self?.handleEnded()
        }
        if let mixer = engine as? MixCapableEngine {
            mixer.onMixStarted = { [weak self] track, index in
                self?.mix = ActiveMix(track: track, index: index, progress: 0)
            }
            mixer.onMixProgress = { [weak self] progress in
                self?.setMixProgress(progress)
            }
            mixer.onMixHandover = { [weak self] index, time in
                self?.adoptMixed(index: index, time: time)
            }
            mixer.onMixCancel = { [weak self] in
                self?.mix = nil
            }
        }
    }

    func time(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(duration > 0 ? duration : .greatestFiniteMagnitude, position + date.timeIntervalSince(syncDate))
    }

    func toggleAutoMix() {
        setAutoMix(!autoMix)
    }

    func setAutoMix(_ value: Bool) {
        SoundSettings.shared.setAutoMix(value)
        if !value {
            cancelActiveMix()
        }
    }

    func cancelActiveMix() {
        (engine as? MixCapableEngine)?.cancelMix()
        mix = nil
    }

    func play(_ track: TrackRecord, in list: [TrackRecord]) {
        queue = list.contains(where: { $0.id == track.id }) ? list : [track] + list
        currentIndex = queue.firstIndex(where: { $0.id == track.id })
        history.removeAll()
        nextPin = nil
        startCurrent(autoplay: true)
    }

    func togglePlay() {
        guard current != nil else { return }
        if isPlaying {
            engine?.pause()
            position = engine?.currentTime ?? position
            isPlaying = false
            syncDate = Date()
            stopTicker()
        } else {
            engine?.play()
            isPlaying = true
            syncDate = Date()
            startTicker()
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        nextPin = nil
        if repeatMode == .one {
            startCurrent(autoplay: true)
            return
        }
        if shuffle, queue.count > 1 {
            var candidate = Int.random(in: 0..<queue.count)
            if candidate == currentIndex {
                candidate = (candidate + 1) % queue.count
            }
            if let index = currentIndex {
                history.append(index)
                if history.count > 50 {
                    history.removeFirst()
                }
            }
            currentIndex = candidate
            startCurrent(autoplay: true)
            return
        }
        let following = (currentIndex ?? -1) + 1
        if following < queue.count {
            currentIndex = following
            startCurrent(autoplay: true)
        } else if repeatMode == .all {
            currentIndex = 0
            startCurrent(autoplay: true)
        } else {
            mix = nil
            isPlaying = false
            position = 0
            engine?.stop()
            stopTicker()
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if position > 3 || currentIndex == nil {
            seek(to: 0)
            return
        }
        nextPin = nil
        if shuffle, let last = history.popLast() {
            currentIndex = last
        } else if let index = currentIndex, index > 0 {
            currentIndex = index - 1
        } else {
            seek(to: 0)
            return
        }
        startCurrent(autoplay: true)
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        engine?.seek(to: clamped)
        mix = nil
        position = clamped
        syncDate = Date()
        seekToken += 1
    }

    func resume() {
        if !isPlaying {
            togglePlay()
        }
    }

    func pause() {
        if isPlaying {
            togglePlay()
        }
    }

    func toggleShuffle() {
        shuffle.toggle()
        resetPreparedMix()
    }

    func cycleRepeat() {
        repeatMode = repeatMode.next
        resetPreparedMix()
    }

    func playNext(_ track: TrackRecord) {
        guard let index = currentIndex else {
            play(track, in: [track])
            return
        }
        queue.insert(track, at: index + 1)
        resetPreparedMix()
    }

    func addToQueue(_ track: TrackRecord) {
        if queue.isEmpty {
            play(track, in: [track])
        } else {
            queue.append(track)
            resetPreparedMix()
        }
    }

    func remove(at index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        queue.remove(at: index)
        if let current = currentIndex, index < current {
            currentIndex = current - 1
        }
        resetPreparedMix()
    }

    func clearUpcoming() {
        guard let index = currentIndex else {
            queue.removeAll()
            resetPreparedMix()
            return
        }
        queue = Array(queue.prefix(index + 1))
        resetPreparedMix()
    }

    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        nextPin = nil
        currentIndex = index
        startCurrent(autoplay: true)
    }

    func updateTrack(_ track: TrackRecord) {
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            queue[index] = track
        }
    }

    private func resetPreparedMix() {
        nextPin = nil
        (engine as? MixCapableEngine)?.cancelPrepared()
    }

    private func pickEngine(for track: TrackRecord) -> PlaybackEngine? {
        if track.isRemote || track.usesSystemDecoder {
            return remoteEngine ?? localEngine
        }
        if autoMix, track.supportsAVPlayer, let remoteEngine {
            return remoteEngine
        }
        return localEngine
    }

    private func startCurrent(autoplay: Bool) {
        guard let track = current else { return }
        mix = nil
        duration = track.durationSeconds
        position = 0
        syncDate = Date()
        let wanted = pickEngine(for: track)
        if let active = engine, let wanted, active !== wanted {
            active.stop()
        }
        if let wanted {
            engine = wanted
        }
        (engine as? MixCapableEngine)?.clearBlocked()
        engine?.load(track, autoplay: autoplay)
        isPlaying = autoplay
        if autoplay {
            startTicker()
        } else {
            stopTicker()
        }
        seekToken += 1
        if autoMix, engine is MixCapableEngine {
            AutoMixAnalyzer.shared.study(track, duration: duration)
        }
        onTrackStarted?(track)
    }

    private func setMixProgress(_ value: Double) {
        guard var currentMix = mix else { return }
        if value < 1.0 && abs(currentMix.progress - value) < 0.015 {
            return
        }
        currentMix.progress = value
        mix = currentMix
    }

    private func adoptMixed(index: Int, time: Double) {
        guard queue.indices.contains(index) else {
            mix = nil
            return
        }
        if shuffle, let previous = currentIndex, previous != index {
            history.append(previous)
            if history.count > 50 {
                history.removeFirst()
            }
        }
        nextPin = nil
        currentIndex = index
        let track = queue[index]
        position = time
        let total = engine?.totalTime ?? 0
        duration = total > 0 ? total : track.durationSeconds
        syncDate = Date()
        mix = nil
        seekToken += 1
        onTrackStarted?(track)
    }

    func chooseNextIndex() -> Int? {
        guard let index = currentIndex, queue.indices.contains(index) else { return nil }
        if repeatMode == .one {
            return index
        }
        if shuffle, queue.count > 1 {
            let currentId = queue[index].id
            if let pin = nextPin, pin.fromId == currentId,
               let match = queue.indices.first(where: { $0 != index && queue[$0].id == pin.toId }) {
                return match
            }
            let choices = queue.indices.filter { $0 != index }
            guard let pick = choices.randomElement() else { return nil }
            nextPin = (fromId: currentId, toId: queue[pick].id)
            return pick
        }
        nextPin = nil
        let following = index + 1
        if following < queue.count {
            return following
        }
        if repeatMode == .all {
            return 0
        }
        return nil
    }

    private func makeMixTrack(_ track: TrackRecord, duration: Double, clearAlbum: Bool) -> MixTrack {
        MixTrack(
            duration: duration,
            album: clearAlbum ? "" : (track.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
            trackNumber: track.trackNumber ?? 0,
            discNumber: track.discNumber ?? 0,
            genre: track.genre?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            ends: AutoMixAnalyzer.shared.ends(for: track, duration: duration)
        )
    }

    private func watchMix(time: Double) {
        guard autoMix, isPlaying, endedHandler == nil,
              let track = current, let currentIdx = currentIndex else { return }
        guard let mixer = engine as? MixCapableEngine, !mixer.isMixing else { return }
        guard !track.isDolbyAtmos else { return }
        guard let index = chooseNextIndex(), !mixer.isBlocked(index: index), queue.indices.contains(index) else { return }
        let incoming = queue[index]
        guard !incoming.isDolbyAtmos, incoming.isRemote || incoming.usesSystemDecoder || incoming.supportsAVPlayer else { return }

        let outDuration = duration > 0 ? duration : track.durationSeconds
        let inDuration = incoming.durationSeconds
        AutoMixAnalyzer.shared.study(track, duration: outDuration)
        AutoMixAnalyzer.shared.study(incoming, duration: inDuration)

        let again = index == currentIdx
        let plan = AutoMix.plan(
            out: makeMixTrack(track, duration: outDuration, clearAlbum: false),
            incoming: makeMixTrack(incoming, duration: inDuration, clearAlbum: again),
            shuffle: shuffle
        )
        guard plan.kind != .none else { return }

        if AutoMix.shouldPreload(time: time, plan: plan, prepared: mixer.isPrepared(for: index)) {
            mixer.prepareMix(track: incoming, index: index, offset: plan.inOffset)
        }
        if AutoMix.shouldStart(time: time, plan: plan, mixing: false) {
            mixer.startMix(plan: plan, track: incoming, index: index)
            return
        }
        if AutoMix.shouldStart(time: time + 0.35, plan: plan, mixing: false) {
            if !mixer.isPrepared(for: index) {
                mixer.prepareMix(track: incoming, index: index, offset: plan.inOffset)
            }
            mixer.armMix(plan: plan, track: incoming, index: index)
        }
    }

    private func handleEnded() {
        if let handler = endedHandler, handler() {
            return
        }
        next()
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let engine, isPlaying else { return }
        position = engine.currentTime
        let total = engine.totalTime
        if total > 0 {
            duration = total
        }
        syncDate = Date()
        watchMix(time: position)
    }
}
