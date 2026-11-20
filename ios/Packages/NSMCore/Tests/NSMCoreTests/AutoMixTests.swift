import Foundation
import XCTest
@testable import NSMCore

final class AutoMixTests: XCTestCase {
    private func makeEnds(
        intro: Double = 0,
        outro: Double = 4,
        bpm: Double = 120,
        headBeat: Double = 0.5,
        tailBeat: Double = 190,
        key: Int = 0,
        mode: Int = 1
    ) -> MixEnds {
        MixEnds(intro: intro, outro: outro, bpm: bpm, headBeat: headBeat, tailBeat: tailBeat, key: key, mode: mode)
    }

    private func makeTrack(
        duration: Double = 200,
        album: String = "Singles",
        trackNumber: Int = 1,
        discNumber: Int = 1,
        genre: String = "pop",
        ends: MixEnds? = nil
    ) -> MixTrack {
        MixTrack(
            duration: duration,
            album: album,
            trackNumber: trackNumber,
            discNumber: discNumber,
            genre: genre,
            ends: ends ?? makeEnds()
        )
    }

    private func makeKicks(bpm: Double, first: Double, seconds: Double, rate: Double) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(rate * seconds))
        let step = 60.0 / bpm
        var time = first
        while time < seconds - 0.1 {
            let at = Int(time * rate)
            let kickLen = Int(rate * 0.06)
            for i in 0..<kickLen where at + i < samples.count {
                let s = sin((2.0 * .pi * 60.0 * Double(i)) / rate) * exp(-Double(i) / (rate * 0.02))
                samples[at + i] += Float(s)
            }
            if Int(((time - first) / step).rounded()) % 2 == 1 {
                let hatLen = Int(rate * 0.02)
                for i in 0..<hatLen where at + i < samples.count {
                    samples[at + i] += i % 3 == 0 ? 0.3 : -0.2
                }
            }
            time += step
        }
        return samples
    }

    func testBeatMatchesEarlyAndLinesUpDownbeats() {
        let outgoing = makeTrack(duration: 200, trackNumber: 3)
        let incoming = makeTrack(
            duration: 180,
            album: "Other",
            trackNumber: 1,
            ends: makeEnds(intro: 0.5, outro: 2, bpm: 124, headBeat: 0.5, tailBeat: 170)
        )
        let plan = AutoMix.plan(out: outgoing, incoming: incoming, shuffle: false)
        XCTAssertEqual(plan.kind, .beat)
        XCTAssertEqual(plan.outStart, 181.0, accuracy: 1e-5)
        XCTAssertEqual(plan.overlap, 12.0, accuracy: 1e-5)
        XCTAssertEqual(plan.inOffset, 0.5, accuracy: 1e-5)
        XCTAssertEqual(plan.inRate, 120.0 / 124.0, accuracy: 1e-5)
        XCTAssertEqual(plan.outRate, sqrt(124.0 / 120.0), accuracy: 1e-5)
        XCTAssertNotNil(plan.sync)
    }

    func testFallsBackToBlendWithoutGridOrFarTempo() {
        let outgoing = makeTrack(duration: 200, trackNumber: 3)
        let far = makeTrack(duration: 180, album: "Other", ends: makeEnds(bpm: 85, headBeat: 0.5))
        let farPlan = AutoMix.plan(out: outgoing, incoming: far, shuffle: false)
        XCTAssertEqual(farPlan.kind, .blend)
        XCTAssertEqual(farPlan.inRate, 1.0)
        XCTAssertEqual(farPlan.outRate, 1.0)

        let blind = makeTrack(duration: 180, album: "Other", ends: makeEnds(bpm: 124, headBeat: -1, tailBeat: -1))
        XCTAssertEqual(AutoMix.plan(out: outgoing, incoming: blind, shuffle: false).kind, .blend)
    }

    func testLeavesOrderedAlbumAlone() {
        let first = makeTrack(duration: 200, album: "Album", trackNumber: 1, discNumber: 1)
        let second = makeTrack(duration: 200, album: "Album", trackNumber: 2, discNumber: 1)
        let nextDisc = makeTrack(duration: 200, album: "Album", trackNumber: 1, discNumber: 2)
        XCTAssertEqual(AutoMix.plan(out: first, incoming: second, shuffle: false).kind, .none)
        XCTAssertEqual(AutoMix.plan(out: second, incoming: nextDisc, shuffle: false).kind, .none)
        XCTAssertEqual(AutoMix.plan(out: first, incoming: second, shuffle: true).kind, .beat)
    }

    func testDoesNotMixShortTrack() {
        let short = makeTrack(duration: 20)
        let normal = makeTrack(duration: 180, album: "Other")
        XCTAssertEqual(AutoMix.plan(out: short, incoming: normal, shuffle: false).kind, .none)
    }

    func testHalfTimeMatchAndKeysAndGenres() {
        XCTAssertEqual(AutoMix.matchRate(outBpm: 140, inBpm: 70), 1.0, accuracy: 1e-5)
        XCTAssertTrue(AutoMix.keysFit(makeEnds(key: 0, mode: 1), makeEnds(key: 9, mode: 0)))
        XCTAssertFalse(AutoMix.keysFit(makeEnds(key: 0, mode: 1), makeEnds(key: 6, mode: 1)))
        XCTAssertTrue(AutoMix.keysFit(makeEnds(key: -1, mode: -1), makeEnds(key: 6, mode: 1)))
        XCTAssertTrue(AutoMix.genresClash("Classical", "Heavy Metal"))
        XCTAssertFalse(AutoMix.genresClash("Pop", "Electronic"))
    }

    func testEqualPowerCurveAndBassSwap() {
        let mid = AutoMix.curve(kind: .beat, progress: 0.5)
        XCTAssertEqual(mid.outGain * mid.outGain + mid.inGain * mid.inGain, 1.0, accuracy: 1e-9)
        XCTAssertLessThan(AutoMix.curve(kind: .beat, progress: 0).inBass, -10)
        XCTAssertEqual(AutoMix.curve(kind: .beat, progress: 1).inBass, 0, accuracy: 1e-9)
        XCTAssertLessThan(AutoMix.curve(kind: .beat, progress: 1).outHz, 1000)
    }

    func testReadsNonRoundTempoAndPhasePrecisely() {
        let rate = 11025.0
        let samples = makeKicks(bpm: 123.4, first: 0.37, seconds: 32, rate: rate)
        let read = AutoMix.readRegion(samples: samples, sampleRate: rate, region: .tail, regionStart: 100, fullDuration: 132)
        XCTAssertLessThan(abs(read.ends.bpm - 123.4), 0.3)
        let step = 60.0 / 123.4
        let shift = (read.ends.tailBeat - 100.0 - 0.37 + step * 100.0).truncatingRemainder(dividingBy: step)
        let error = min(shift, step - shift)
        XCTAssertLessThan(error, 0.02)
    }

    func testMeasuresDeadTailAndCMajorTriad() {
        let rate = 8000.0
        var tail = [Float](repeating: 0, count: Int(rate * 3))
        for i in 0..<Int(rate * 2) {
            tail[i] = Float(sin((2.0 * .pi * 220.0 * Double(i)) / rate) * 0.4)
        }
        let tailRead = AutoMix.readRegion(samples: tail, sampleRate: rate, region: .tail, regionStart: 0, fullDuration: 3)
        XCTAssertGreaterThan(tailRead.ends.outro, 0.8)
        XCTAssertLessThan(tailRead.ends.outro, 1.3)

        var triad = [Float](repeating: 0, count: Int(rate * 0.8))
        let freqs = [261.63, 329.63, 392.0]
        for i in 0..<triad.count {
            var value = 0.0
            for f in freqs { value += sin((2.0 * .pi * f * Double(i)) / rate) }
            triad[i] = Float(value / 3.0)
        }
        let keyRead = AutoMix.readRegion(samples: triad, sampleRate: rate, region: .head, regionStart: 0, fullDuration: 0.8)
        XCTAssertEqual(keyRead.ends.key, 0)
        XCTAssertEqual(keyRead.ends.mode, 1)
    }

    func testMergeRegionsKeepsSameTempoGrid() {
        let rate = 11025.0
        let head = AutoMix.readRegion(samples: makeKicks(bpm: 98.6, first: 0.2, seconds: 20, rate: rate), sampleRate: rate, region: .head, regionStart: 0, fullDuration: 200)
        let tail = AutoMix.readRegion(samples: makeKicks(bpm: 98.6, first: 0.55, seconds: 32, rate: rate), sampleRate: rate, region: .tail, regionStart: 168, fullDuration: 200)
        let merged = AutoMix.mergeRegions(head: head, tail: tail)
        XCTAssertLessThan(abs(merged.bpm - 98.6), 0.3)
        XCTAssertGreaterThanOrEqual(merged.headBeat, 0)
        XCTAssertGreaterThanOrEqual(merged.tailBeat, 168)
    }

    func testPhaseLockCorrectsInitialDriftAndNudgesLater() {
        let sync = MixSync(outBeat: 10, outStep: 0.5, inBeat: 0.5, inStep: 0.5, scale: 1.0, ratio: 1.0, outEnd: 22)
        let initial = AutoMix.phaseLock(progress: 0.02, outTime: 10.5, inTime: 1.08, outRateTarget: 1.0, sync: sync, hardFixed: false)
        XCTAssertEqual(initial.seekTo ?? -1, 1.0, accuracy: 1e-5)
        XCTAssertTrue(initial.markFixed)

        let nudged = AutoMix.phaseLock(progress: 0.5, outTime: 15.0, inTime: 5.55, outRateTarget: 1.0, sync: sync, hardFixed: true)
        XCTAssertNil(nudged.seekTo)
        XCTAssertLessThan(nudged.inRate, 1.0)
    }
}
