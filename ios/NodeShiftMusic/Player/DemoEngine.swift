import Foundation

@MainActor
final class DemoEngine: PlaybackEngine {
    var onEnded: (() -> Void)?
    private var track: TrackRecord?
    private var startedAt = Date()
    private var offset = 0.0
    private var playing = false

    var totalTime: Double {
        track?.durationSeconds ?? 0
    }

    var currentTime: Double {
        let value = playing ? offset + Date().timeIntervalSince(startedAt) : offset
        if totalTime > 0, value >= totalTime {
            playing = false
            offset = totalTime
            Task { @MainActor [weak self] in
                self?.onEnded?()
            }
            return totalTime
        }
        return value
    }

    func load(_ track: TrackRecord, autoplay: Bool) {
        self.track = track
        offset = 0
        startedAt = Date()
        playing = autoplay
    }

    func play() {
        if !playing {
            startedAt = Date()
            playing = true
        }
    }

    func pause() {
        offset = currentTime
        playing = false
    }

    func seek(to seconds: Double) {
        offset = seconds
        startedAt = Date()
    }

    func stop() {
        playing = false
        offset = 0
    }
}
