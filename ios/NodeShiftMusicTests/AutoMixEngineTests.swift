import Foundation
import XCTest
import NSMCore
@testable import NodeShiftMusic

@MainActor
private final class MockMixEngine: MixCapableEngine {
    var currentTime: Double = 0
    var totalTime: Double = 200
    var onEnded: (() -> Void)?
    var onMixStarted: ((TrackRecord, Int) -> Void)?
    var onMixProgress: ((Double) -> Void)?
    var onMixHandover: ((Int, Double) -> Void)?
    var onMixCancel: (() -> Void)?
    var isMixing = false
    var preparedIndex = -1
    var cancelCount = 0
    var prepareCount = 0
    var startCount = 0
    var lastLoaded: TrackRecord?

    func load(_ track: TrackRecord, autoplay: Bool) {
        lastLoaded = track
        currentTime = 0
        totalTime = track.durationSeconds
    }

    func play() {}
    func pause() {}
    func seek(to seconds: Double) { currentTime = seconds }
    func stop() { isMixing = false }

    func isPrepared(for index: Int) -> Bool { preparedIndex == index }
    func isBlocked(index: Int) -> Bool { false }
    func clearBlocked() {}

    func prepareMix(track: TrackRecord, index: Int, offset: Double) {
        preparedIndex = index
        prepareCount += 1
    }

    func armMix(plan: MixPlan, track: TrackRecord, index: Int) {}

    func startMix(plan: MixPlan, track: TrackRecord, index: Int) {
        isMixing = true
        startCount += 1
        onMixStarted?(track, index)
    }

    func cancelMix() {
        let was = isMixing
        isMixing = false
        preparedIndex = -1
        cancelCount += 1
        if was {
            onMixCancel?()
        }
    }

    func cancelPrepared() {
        if !isMixing {
            preparedIndex = -1
        }
    }
}

final class AutoMixEngineTests: XCTestCase {
    func testDeckDSPAttenuatesHighsAndBass() {
        var dsp = DeckDSPState()
        dsp.sampleRate = 44100
        dsp.supported = 1
        dsp.active = 1
        dsp.targetHz = 900
        dsp.targetBassDb = -14
        dsp.curHz = 900
        dsp.curBassDb = -14
        dsp.recomputeCoeffs()

        let count = 2048
        var high = [Float](repeating: 0, count: count)
        var bass = [Float](repeating: 0, count: count)
        for i in 0..<count {
            high[i] = Float(sin(2.0 * .pi * 8000.0 * Double(i) / 44100.0))
            bass[i] = Float(sin(2.0 * .pi * 60.0 * Double(i) / 44100.0))
        }
        high.withUnsafeMutableBufferPointer { buf in
            dsp.filterChannel(buf.baseAddress!, count: count, stride: 1, right: false)
        }
        dsp.resetDelays()
        bass.withUnsafeMutableBufferPointer { buf in
            dsp.filterChannel(buf.baseAddress!, count: count, stride: 1, right: false)
        }

        let highRms = sqrt(high.suffix(512).reduce(0.0) { $0 + Double($1 * $1) } / 512.0)
        let bassRms = sqrt(bass.suffix(512).reduce(0.0) { $0 + Double($1 * $1) } / 512.0)
        XCTAssertLessThan(highRms, 0.1)
        XCTAssertLessThan(bassRms, 0.25)
    }

    @MainActor
    func testRepeatOneAndHandoverAndToggleOff() {
        let saved = SoundSettings.shared.autoMix
        defer { SoundSettings.shared.setAutoMix(saved) }
        SoundSettings.shared.setAutoMix(true)

        let player = PlayerStore()
        let mock = MockMixEngine()
        player.attach(DemoEngine())
        player.attachRemote(mock)

        var first = TrackRecord.blank(id: "a")
        first.title = "First"
        first.format = "flac"
        first.durationMs = 200_000
        var second = TrackRecord.blank(id: "b")
        second.title = "Second"
        second.format = "mp3"
        second.durationMs = 180_000

        var started: [String] = []
        player.onTrackStarted = { started.append($0.id) }
        player.play(first, in: [first, second])
        XCTAssertEqual(mock.lastLoaded?.id, "a")

        player.repeatMode = .one
        XCTAssertEqual(player.chooseNextIndex(), 0)

        player.repeatMode = .off
        XCTAssertEqual(player.chooseNextIndex(), 1)

        mock.onMixStarted?(second, 1)
        XCTAssertEqual(player.mix?.track.id, "b")
        mock.onMixProgress?(0.5)
        XCTAssertEqual(player.mix?.progress ?? 0, 0.5, accuracy: 1e-6)

        let beforeToken = player.seekToken
        mock.onMixHandover?(1, 11.4)
        XCTAssertNil(player.mix)
        XCTAssertEqual(player.currentIndex, 1)
        XCTAssertEqual(player.position, 11.4, accuracy: 1e-6)
        XCTAssertGreaterThan(player.seekToken, beforeToken)
        XCTAssertEqual(started.last, "b")

        mock.isMixing = true
        mock.onMixStarted?(first, 0)
        player.setAutoMix(false)
        XCTAssertFalse(mock.isMixing)
        XCTAssertNil(player.mix)
        player.pause()
    }
}
