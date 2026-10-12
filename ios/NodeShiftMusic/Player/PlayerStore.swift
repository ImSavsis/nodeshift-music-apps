import Foundation
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
@Observable
final class PlayerStore {
    var queue: [TrackRecord] = []
    var currentIndex: Int?
    var isPlaying = false
    var position: Double = 0
    var duration: Double = 0
    var shuffle = false
    var repeatMode: RepeatMode = .off
    var isFullPlayerOpen = false
    var isQueueOpen = false
    var syncDate = Date()
    var seekToken = 0

    @ObservationIgnored private var engine: PlaybackEngine?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var history: [Int] = []
    @ObservationIgnored var onTrackStarted: ((TrackRecord) -> Void)?

    var current: TrackRecord? {
        guard let index = currentIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    var upcomingCount: Int {
        guard let index = currentIndex else { return queue.count }
        return max(0, queue.count - index - 1)
    }

    func attach(_ engine: PlaybackEngine) {
        self.engine = engine
        engine.onEnded = { [weak self] in
            self?.handleEnded()
        }
    }

    func time(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(duration > 0 ? duration : .greatestFiniteMagnitude, position + date.timeIntervalSince(syncDate))
    }

    func play(_ track: TrackRecord, in list: [TrackRecord]) {
        queue = list.contains(where: { $0.id == track.id }) ? list : [track] + list
        currentIndex = queue.firstIndex(where: { $0.id == track.id })
        history.removeAll()
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
    }

    func cycleRepeat() {
        repeatMode = repeatMode.next
    }

    func playNext(_ track: TrackRecord) {
        guard let index = currentIndex else {
            play(track, in: [track])
            return
        }
        queue.insert(track, at: index + 1)
    }

    func addToQueue(_ track: TrackRecord) {
        if queue.isEmpty {
            play(track, in: [track])
        } else {
            queue.append(track)
        }
    }

    func remove(at index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        queue.remove(at: index)
        if let current = currentIndex, index < current {
            currentIndex = current - 1
        }
    }

    func clearUpcoming() {
        guard let index = currentIndex else {
            queue.removeAll()
            return
        }
        queue = Array(queue.prefix(index + 1))
    }

    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        startCurrent(autoplay: true)
    }

    func updateTrack(_ track: TrackRecord) {
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            queue[index] = track
        }
    }

    private func startCurrent(autoplay: Bool) {
        guard let track = current else { return }
        duration = track.durationSeconds
        position = 0
        syncDate = Date()
        engine?.load(track, autoplay: autoplay)
        isPlaying = autoplay
        if autoplay {
            startTicker()
        } else {
            stopTicker()
        }
        seekToken += 1
        onTrackStarted?(track)
    }

    private func handleEnded() {
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
    }
}
