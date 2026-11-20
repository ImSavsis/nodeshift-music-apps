import Foundation

public struct MixEnds: Equatable, Sendable {
    public var intro: Double
    public var outro: Double
    public var bpm: Double
    public var headBeat: Double
    public var tailBeat: Double
    public var key: Int
    public var mode: Int

    public init(
        intro: Double,
        outro: Double,
        bpm: Double,
        headBeat: Double,
        tailBeat: Double,
        key: Int,
        mode: Int
    ) {
        self.intro = intro
        self.outro = outro
        self.bpm = bpm
        self.headBeat = headBeat
        self.tailBeat = tailBeat
        self.key = key
        self.mode = mode
    }

    public static let empty = MixEnds(
        intro: 0,
        outro: 0,
        bpm: 0,
        headBeat: -1,
        tailBeat: -1,
        key: -1,
        mode: -1
    )
}

public struct MixTrack: Equatable, Sendable {
    public var duration: Double
    public var album: String
    public var trackNumber: Int
    public var discNumber: Int
    public var genre: String
    public var ends: MixEnds

    public init(
        duration: Double,
        album: String,
        trackNumber: Int,
        discNumber: Int,
        genre: String,
        ends: MixEnds
    ) {
        self.duration = duration
        self.album = album
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.genre = genre
        self.ends = ends
    }
}

public enum MixKind: String, Equatable, Sendable {
    case none
    case beat
    case blend
}

public struct MixSync: Equatable, Sendable {
    public var outBeat: Double
    public var outStep: Double
    public var inBeat: Double
    public var inStep: Double
    public var scale: Double
    public var ratio: Double
    public var outEnd: Double

    public init(
        outBeat: Double,
        outStep: Double,
        inBeat: Double,
        inStep: Double,
        scale: Double,
        ratio: Double,
        outEnd: Double
    ) {
        self.outBeat = outBeat
        self.outStep = outStep
        self.inBeat = inBeat
        self.inStep = inStep
        self.scale = scale
        self.ratio = ratio
        self.outEnd = outEnd
    }
}

public struct MixPlan: Equatable, Sendable {
    public var kind: MixKind
    public var outStart: Double
    public var overlap: Double
    public var inOffset: Double
    public var inRate: Double
    public var outRate: Double
    public var sync: MixSync?

    public init(
        kind: MixKind,
        outStart: Double,
        overlap: Double,
        inOffset: Double,
        inRate: Double,
        outRate: Double,
        sync: MixSync?
    ) {
        self.kind = kind
        self.outStart = outStart
        self.overlap = overlap
        self.inOffset = inOffset
        self.inRate = inRate
        self.outRate = outRate
        self.sync = sync
    }

    public static func none(at duration: Double) -> MixPlan {
        MixPlan(kind: .none, outStart: duration, overlap: 0, inOffset: 0, inRate: 1, outRate: 1, sync: nil)
    }
}

public struct MixCurve: Equatable, Sendable {
    public var outGain: Double
    public var inGain: Double
    public var outHz: Double
    public var outBass: Double
    public var inBass: Double

    public init(outGain: Double, inGain: Double, outHz: Double, outBass: Double, inBass: Double) {
        self.outGain = outGain
        self.inGain = inGain
        self.outHz = outHz
        self.outBass = outBass
        self.inBass = inBass
    }
}

public enum MixRegion: Sendable {
    case head
    case tail
}

public struct RegionGrid: Equatable, Sendable {
    public var soft: [Float]
    public var start: Double
    public var notBefore: Double

    public init(soft: [Float], start: Double, notBefore: Double) {
        self.soft = soft
        self.start = start
        self.notBefore = notBefore
    }
}

public struct RegionRead: Equatable, Sendable {
    public var ends: MixEnds
    public var confidence: Double
    public var loud: Double
    public var grid: RegionGrid?

    public init(ends: MixEnds, confidence: Double, loud: Double, grid: RegionGrid? = nil) {
        self.ends = ends
        self.confidence = confidence
        self.loud = loud
        self.grid = grid
    }
}

public struct PhaseLockResult: Equatable, Sendable {
    public var outRate: Double
    public var inRate: Double
    public var seekTo: Double?
    public var markFixed: Bool

    public init(outRate: Double, inRate: Double, seekTo: Double?, markFixed: Bool) {
        self.outRate = outRate
        self.inRate = inRate
        self.seekTo = seekTo
        self.markFixed = markFixed
    }
}

public enum AutoMix {
    public static let minDuration = 28.0
    public static let minOverlap = 4.0
    public static let maxOverlap = 20.0
    public static let maxStretch = 0.12
    public static let blendOverlap = 11.0
    public static let beatCount = 24.0
    public static let earlyLead = 3.0
    public static let preloadLead = 12.0
    public static let headSeconds = 20.0
    public static let tailSeconds = 32.0

    private static let gridRate = 200.0
    private static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.6, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    private static let calmWords = ["classical", "jazz", "ambient", "soundtrack", "folk", "acoustic", "классик", "джаз", "эмбиент"]
    private static let heavyWords = ["metal", "hardcore", "punk", "grind", "метал", "хардкор", "панк"]

    private static func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double) -> Double {
        min(maxValue, max(minValue, value))
    }

    private static func includesAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    public static func matchRate(outBpm: Double, inBpm: Double) -> Double {
        guard outBpm > 0, inBpm > 0 else { return 0 }
        var best = 0.0
        var bestDistance = Double.infinity
        for factor in [1.0, 0.5, 2.0] {
            let rate = (outBpm * factor) / inBpm
            if rate < 1.0 - maxStretch || rate > 1.0 + maxStretch {
                continue
            }
            let distance = abs(log(rate)) + (factor == 1.0 ? 0.0 : 0.001)
            if distance < bestDistance {
                bestDistance = distance
                best = rate
            }
        }
        return best
    }

    public static func keysFit(_ out: MixEnds, _ incoming: MixEnds) -> Bool {
        if out.key < 0 || incoming.key < 0 { return true }
        let interval = (incoming.key - out.key + 12) % 12
        if interval == 0 { return true }
        let sameMode = out.mode < 0 || incoming.mode < 0 || out.mode == incoming.mode
        if sameMode && (interval == 5 || interval == 7 || interval == 2 || interval == 10) { return true }
        if out.mode == 1 && incoming.mode == 0 && interval == 9 { return true }
        if out.mode == 0 && incoming.mode == 1 && interval == 3 { return true }
        return false
    }

    public static func genresClash(_ left: String, _ right: String) -> Bool {
        let a = left.lowercased()
        let b = right.lowercased()
        if a.isEmpty || b.isEmpty { return false }
        let calmA = includesAny(a, calmWords)
        let calmB = includesAny(b, calmWords)
        let heavyA = includesAny(a, heavyWords)
        let heavyB = includesAny(b, heavyWords)
        return (calmA && heavyB) || (heavyA && calmB)
    }

    public static func albumRun(out: MixTrack, incoming: MixTrack, shuffle: Bool) -> Bool {
        if shuffle { return false }
        let left = out.album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right = incoming.album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if left.isEmpty || left != right { return false }
        let discOut = out.discNumber > 0 ? out.discNumber : 1
        let discIn = incoming.discNumber > 0 ? incoming.discNumber : 1
        if out.trackNumber > 0 && incoming.trackNumber > 0 {
            if discOut == discIn && incoming.trackNumber == out.trackNumber + 1 { return true }
            if discIn == discOut + 1 && incoming.trackNumber == 1 { return true }
            return false
        }
        return true
    }

    public static func plan(out: MixTrack, incoming: MixTrack, shuffle: Bool) -> MixPlan {
        if albumRun(out: out, incoming: incoming, shuffle: shuffle) {
            return .none(at: out.duration)
        }
        if out.duration < minDuration || incoming.duration < minDuration {
            return .none(at: out.duration)
        }

        let rawOutro = clamp(out.ends.outro, 0, 25)
        let lead = rawOutro >= 8 ? 1.5 : earlyLead
        let outro = clamp(rawOutro + lead, 0, 28)
        let intro = clamp(incoming.ends.intro, 0, incoming.duration * 0.25)
        let outEnd = max(0, out.duration - outro)
        let inBody = incoming.duration - intro - clamp(incoming.ends.outro, 0, 25)
        if outEnd < 18 || inBody < 12 {
            return .none(at: out.duration)
        }

        let rate = matchRate(outBpm: out.ends.bpm, inBpm: incoming.ends.bpm)
        let gridded = out.ends.tailBeat >= 0 && incoming.ends.headBeat >= 0
        let beat = rate > 0 && gridded && keysFit(out.ends, incoming.ends) && !genresClash(out.genre, incoming.genre)
        var overlap = beat ? clamp(beatCount * (60.0 / out.ends.bpm), 8.0, maxOverlap) : blendOverlap
        let maxAllowed = min(outEnd * 0.45, inBody * 0.45, maxOverlap)
        if maxAllowed < minOverlap {
            return .none(at: out.duration)
        }
        overlap = min(overlap, maxAllowed)

        var outStart = outEnd - overlap
        let earliest = min(out.duration * 0.4, outEnd - minOverlap)
        if outStart < earliest {
            outStart = earliest
            overlap = outEnd - outStart
        }
        if overlap < minOverlap {
            return .none(at: out.duration)
        }

        if beat {
            let step = 60.0 / out.ends.bpm
            let shifts = ((outStart - out.ends.tailBeat) / step).rounded()
            var snapped = out.ends.tailBeat + shifts * step
            if snapped > outStart + 0.02 {
                snapped -= step
            }
            let snappedOverlap = outEnd - snapped
            if snapped >= earliest && snappedOverlap >= minOverlap && snappedOverlap <= maxOverlap + 0.75 {
                outStart = snapped
                overlap = snappedOverlap
            }
        }

        var inOffset = intro
        if beat {
            let step = 60.0 / incoming.ends.bpm
            var snapped = incoming.ends.headBeat
            if snapped + 0.001 < intro {
                snapped += ceil((intro - snapped) / step - 1e-9) * step
            }
            if snapped < incoming.duration * 0.35 {
                inOffset = snapped
            }
        }

        if !(overlap > 0) || !outStart.isFinite || !inOffset.isFinite {
            return .none(at: out.duration)
        }

        let sync: MixSync?
        if beat {
            let scale = (((rate * incoming.ends.bpm) / out.ends.bpm) * 100.0).rounded() / 100.0
            sync = MixSync(
                outBeat: out.ends.tailBeat,
                outStep: 60.0 / out.ends.bpm,
                inBeat: incoming.ends.headBeat,
                inStep: 60.0 / incoming.ends.bpm,
                scale: scale,
                ratio: rate,
                outEnd: outStart + overlap
            )
        } else {
            sync = nil
        }

        return MixPlan(
            kind: beat ? .beat : .blend,
            outStart: outStart,
            overlap: overlap,
            inOffset: inOffset,
            inRate: beat ? rate : 1.0,
            outRate: beat ? 1.0 / sqrt(rate) : 1.0,
            sync: sync
        )
    }

    public static func curve(kind: MixKind, progress: Double) -> MixCurve {
        let t = clamp(progress, 0, 1)
        let outGain = cos((t * .pi) / 2.0)
        let inGain = sin((t * .pi) / 2.0)
        if kind == .blend {
            return MixCurve(
                outGain: outGain,
                inGain: inGain,
                outHz: 16000.0 + (5000.0 - 16000.0) * t,
                outBass: -4.0 * t,
                inBass: -4.0 * (1.0 - t)
            )
        }
        return MixCurve(
            outGain: outGain,
            inGain: inGain,
            outHz: 14000.0 * pow(900.0 / 14000.0, t),
            outBass: -14.0 * t,
            inBass: -14.0 * (1.0 - t)
        )
    }

    public static func shouldPreload(time: Double, plan: MixPlan, prepared: Bool) -> Bool {
        if prepared || plan.kind == .none { return false }
        return time >= plan.outStart - preloadLead && time < plan.outStart + plan.overlap * 0.65
    }

    public static func shouldStart(time: Double, plan: MixPlan, mixing: Bool) -> Bool {
        if mixing || plan.kind == .none || !(plan.overlap > 0) { return false }
        return time >= plan.outStart && time < plan.outStart + plan.overlap * 0.65
    }

    public static func heuristicEnds(duration: Double, taggedBpm: Double?) -> MixEnds {
        let bpm = (taggedBpm ?? 0) > 0 ? (taggedBpm ?? 0) : 0
        let outro = duration > 0 ? min(2.2, max(0.7, duration * 0.01)) : 0.8
        return MixEnds(intro: 0, outro: outro, bpm: bpm, headBeat: -1, tailBeat: -1, key: -1, mode: -1)
    }

    public static func phaseLock(
        progress: Double,
        outTime: Double,
        inTime: Double,
        outRateTarget: Double,
        sync: MixSync,
        hardFixed: Bool
    ) -> PhaseLockResult {
        let t = clamp(progress, 0, 1)
        let eased = t * t * (3.0 - 2.0 * t)
        let outRate = 1.0 + (outRateTarget - 1.0) * eased
        var drift = (inTime - sync.inBeat) / sync.inStep - ((outTime - sync.outBeat) / sync.outStep) * sync.scale
        drift -= drift.rounded()
        if !hardFixed && t < 0.15 {
            if abs(drift * sync.inStep) > 0.025 {
                let target = max(0, inTime - drift * sync.inStep)
                return PhaseLockResult(outRate: outRate, inRate: sync.ratio * outRate, seekTo: target, markFixed: true)
            }
            let nudge = clamp(drift * 0.3, -0.04, 0.04)
            return PhaseLockResult(outRate: outRate, inRate: sync.ratio * outRate * (1.0 - nudge), seekTo: nil, markFixed: true)
        }
        let nudge = clamp(drift * 0.3, -0.04, 0.04)
        return PhaseLockResult(outRate: outRate, inRate: sync.ratio * outRate * (1.0 - nudge), seekTo: nil, markFixed: false)
    }

    private static func envelopeOf(_ samples: [Float], sampleRate: Double) -> (env: [Float], rate: Double) {
        let rate = 100.0
        let hop = max(1, Int((sampleRate / rate).rounded()))
        let frames = samples.count / hop
        var env = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Double = 0
            let start = frame * hop
            for offset in 0..<hop {
                let sample = Double(samples[start + offset])
                sum += sample * sample
            }
            env[frame] = Float(sqrt(sum / Double(hop)))
        }
        return (env, rate)
    }

    private static func bandOnset(_ samples: [Float], sampleRate: Double) -> [Float] {
        let hop = max(1, Int((sampleRate / gridRate).rounded()))
        let frames = samples.count / hop
        if frames == 0 { return [] }
        let lowCoef = 1.0 - exp((-2.0 * .pi * 150.0) / sampleRate)
        let highCoef = 1.0 - exp((-2.0 * .pi * 2500.0) / sampleRate)
        var low = 0.0
        var smooth = 0.0
        var lowEnergy = [Double](repeating: 0, count: frames)
        var highEnergy = [Double](repeating: 0, count: frames)
        var lowPeak = 1e-12
        var highPeak = 1e-12
        for frame in 0..<frames {
            var lowSum = 0.0
            var highSum = 0.0
            let start = frame * hop
            for offset in 0..<hop {
                let sample = Double(samples[start + offset])
                low += lowCoef * (sample - low)
                smooth += highCoef * (sample - smooth)
                let high = sample - smooth
                lowSum += low * low
                highSum += high * high
            }
            let l = lowSum / Double(hop)
            let h = highSum / Double(hop)
            lowEnergy[frame] = l
            highEnergy[frame] = h
            if l > lowPeak { lowPeak = l }
            if h > highPeak { highPeak = h }
        }
        var onset = [Float](repeating: 0, count: frames)
        var prevLow = 0.0
        var prevHigh = 0.0
        for frame in 0..<frames {
            let nowLow = log(1.0 + (lowEnergy[frame] / lowPeak) * 1000.0)
            let nowHigh = log(1.0 + (highEnergy[frame] / highPeak) * 1000.0)
            onset[frame] = Float(max(0.0, nowLow - prevLow) + max(0.0, nowHigh - prevHigh))
            prevLow = nowLow
            prevHigh = nowHigh
        }
        var soft = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            let prev = frame > 0 ? onset[frame - 1] : 0
            let next = frame + 1 < frames ? onset[frame + 1] : 0
            soft[frame] = 0.25 * prev + 0.5 * onset[frame] + 0.25 * next
        }
        return soft
    }

    private static func combScore(_ soft: [Float], period: Double, phase: Double) -> Double {
        var sum = 0.0
        var count = 0
        let limit = Double(soft.count - 1)
        var cursor = phase
        while cursor < limit {
            let index = Int(cursor)
            let part = cursor - Double(index)
            sum += Double(soft[index]) * (1.0 - part) + Double(soft[index + 1]) * part
            count += 1
            cursor += period
        }
        return count > 0 ? sum / Double(count) : 0
    }

    private static func fitPhase(_ soft: [Float], bpm: Double) -> Double {
        let period = (60.0 * gridRate) / bpm
        var best = -1.0
        var bestPhase = 0.0
        var phase = 0.0
        while phase < period {
            let score = combScore(soft, period: period, phase: phase)
            if score > best {
                best = score
                bestPhase = phase
            }
            phase += 0.25
        }
        return bestPhase
    }

    private static func wideSmooth(_ input: [Float]) -> [Float] {
        let count = input.count
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let m2: Float = i >= 2 ? input[i - 2] : 0
            let m1: Float = i >= 1 ? input[i - 1] : 0
            let p1: Float = i + 1 < count ? input[i + 1] : 0
            let p2: Float = i + 2 < count ? input[i + 2] : 0
            out[i] = 0.1 * m2 + 0.2 * m1 + 0.4 * input[i] + 0.2 * p1 + 0.1 * p2
        }
        return out
    }

    private static func tempoOf(_ soft: [Float]) -> (bpm: Double, confidence: Double) {
        var total = 0.0
        for value in soft { total += Double(value) }
        let mean = total / Double(max(1, soft.count))
        if mean < 1e-6 || soft.count < Int(gridRate * 4.0) {
            return (0, 0)
        }
        let coarse = wideSmooth(soft)
        var bestBpm = 0.0
        var bestScore = 0.0
        for step in 700...1800 {
            let bpm = Double(step) * 0.1
            let period = (60.0 * gridRate) / bpm
            var raw = 0.0
            var phase = 0.0
            while phase < period {
                let value = combScore(coarse, period: period, phase: phase)
                if value > raw { raw = value }
                phase += 1.0
            }
            let score = raw * (bpm >= 90.0 && bpm <= 150.0 ? 1.15 : 1.0)
            if score > bestScore {
                bestScore = score
                bestBpm = bpm
            }
        }
        if bestBpm <= 0 {
            return (0, 0)
        }
        var bestRaw = 0.0
        let lo = max(7000, Int(((bestBpm - 0.35) * 100.0).rounded()))
        let hi = min(18000, Int(((bestBpm + 0.35) * 100.0).rounded()))
        var refinedBpm = bestBpm
        for step in stride(from: lo, through: hi, by: 2) {
            let bpm = Double(step) * 0.01
            let period = (60.0 * gridRate) / bpm
            var raw = 0.0
            var phase = 0.0
            while phase < period {
                let value = combScore(soft, period: period, phase: phase)
                if value > raw { raw = value }
                phase += 0.5
            }
            if raw > bestRaw {
                bestRaw = raw
                refinedBpm = bpm
            }
        }
        let confidence = bestRaw / mean
        if refinedBpm <= 0 || confidence < 1.4 {
            return (0, confidence)
        }
        return (refinedBpm, confidence)
    }

    private static func firstBeat(_ soft: [Float], bpm: Double, notBefore: Double) -> Double {
        let period = 60.0 / bpm
        let phase = fitPhase(soft, bpm: bpm) / gridRate
        if phase >= notBefore { return phase }
        return phase + ceil((notBefore - phase) / period - 1e-9) * period
    }

    private static func pearson(_ left: [Double], _ right: [Double]) -> Double {
        let count = left.count
        var meanLeft = 0.0
        var meanRight = 0.0
        for i in 0..<count {
            meanLeft += left[i]
            meanRight += right[i]
        }
        meanLeft /= Double(count)
        meanRight /= Double(count)
        var num = 0.0
        var denLeft = 0.0
        var denRight = 0.0
        for i in 0..<count {
            let a = left[i] - meanLeft
            let b = right[i] - meanRight
            num += a * b
            denLeft += a * a
            denRight += b * b
        }
        if denLeft == 0 || denRight == 0 { return 0 }
        return num / sqrt(denLeft * denRight)
    }

    private static func goertzelPower(_ samples: [Float], start: Int, end: Int, sampleRate: Double, freq: Double) -> Double {
        let count = end - start
        guard count > 0 else { return 0 }
        let bin = ((Double(count) * freq) / sampleRate).rounded()
        let coefficient = 2.0 * cos((2.0 * .pi * bin) / Double(count))
        var previous = 0.0
        var prior = 0.0
        for index in start..<end {
            let next = Double(samples[index]) + coefficient * previous - prior
            prior = previous
            previous = next
        }
        return previous * previous + prior * prior - coefficient * previous * prior
    }

    private static func readKey(_ samples: [Float], sampleRate: Double, env: [Float], hop: Int) -> (key: Int, mode: Int) {
        if sampleRate < 4000 || env.count < 8 { return (-1, -1) }
        let window = 2048
        var bestStart = 0
        var bestLoud = 0.0
        let frameHop = max(1, hop)
        var start = 0
        while start + window < samples.count {
            var sum = 0.0
            let from = start / frameHop
            let to = min(env.count, (start + window + frameHop - 1) / frameHop)
            for index in from..<to { sum += Double(env[index]) }
            if sum > bestLoud {
                bestLoud = sum
                bestStart = start
            }
            start += window
        }
        var chroma = [Double](repeating: 0, count: 12)
        let sliceEnd = min(samples.count, bestStart + window)
        for midi in 48...84 {
            let freq = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
            if freq >= sampleRate / 2.0 - 30.0 { continue }
            chroma[midi % 12] += goertzelPower(samples, start: bestStart, end: sliceEnd, sampleRate: sampleRate, freq: freq)
        }
        var bestKey = -1
        var bestMode = -1
        var bestScore = 0.55
        for tonic in 0..<12 {
            var rotated = [Double](repeating: 0, count: 12)
            for i in 0..<12 { rotated[i] = chroma[(i + tonic) % 12] }
            let major = pearson(rotated, majorProfile)
            let minor = pearson(rotated, minorProfile)
            if major > bestScore {
                bestScore = major
                bestKey = tonic
                bestMode = 1
            }
            if minor > bestScore {
                bestScore = minor
                bestKey = tonic
                bestMode = 0
            }
        }
        return (bestKey, bestMode)
    }

    public static func readRegion(
        samples: [Float],
        sampleRate: Double,
        region: MixRegion,
        regionStart: Double,
        fullDuration: Double
    ) -> RegionRead {
        let blank = RegionRead(ends: .empty, confidence: 0, loud: 0, grid: nil)
        if samples.count < 8 || !(sampleRate > 0) { return blank }
        let (env, rate) = envelopeOf(samples, sampleRate: sampleRate)
        if env.count < 8 { return blank }
        var peak: Float = 0
        var loud = 0.0
        for value in env {
            if value > peak { peak = value }
            loud += Double(value)
        }
        if peak < 1e-5 { return blank }
        let threshold = peak * 0.2
        var introFrame = 0
        for index in 0..<env.count where env[index] > threshold {
            introFrame = index
            break
        }
        var lastLoud = -1
        for index in 0..<env.count where env[index] > threshold {
            lastLoud = index
        }
        let soft = bandOnset(samples, sampleRate: sampleRate)
        let tempo = tempoOf(soft)
        let notBefore = region == .head ? Double(introFrame) / rate : 0.0
        let beat = tempo.bpm > 0 ? firstBeat(soft, bpm: tempo.bpm, notBefore: notBefore) : -1.0
        let absoluteBeat = beat >= 0 ? regionStart + beat : -1.0
        let loudEnd = lastLoud < 0 ? 0.0 : Double(lastLoud + 1) / rate
        let outro = region == .tail ? clamp(fullDuration - (regionStart + loudEnd), 0, 25) : 0.0
        let key = readKey(samples, sampleRate: sampleRate, env: env, hop: max(1, Int((sampleRate / rate).rounded())))
        let ends = MixEnds(
            intro: region == .head ? Double(introFrame) / rate : 0.0,
            outro: outro,
            bpm: tempo.bpm,
            headBeat: region == .head ? absoluteBeat : -1.0,
            tailBeat: region == .tail ? absoluteBeat : -1.0,
            key: key.key,
            mode: key.mode
        )
        let grid = tempo.bpm > 0 ? RegionGrid(soft: soft, start: regionStart, notBefore: notBefore) : nil
        return RegionRead(ends: ends, confidence: tempo.confidence, loud: loud, grid: grid)
    }

    private static func refit(_ read: RegionRead, bpm: Double, fallback: Double) -> Double {
        guard let grid = read.grid, bpm > 0 else { return fallback }
        return grid.start + firstBeat(grid.soft, bpm: bpm, notBefore: grid.notBefore)
    }

    public static func mergeRegions(head: RegionRead, tail: RegionRead) -> MixEnds {
        let bpmFromHead = head.confidence >= tail.confidence
        let keyFromHead = head.loud >= tail.loud
        let source = bpmFromHead ? head.ends : tail.ends
        let keySource = keyFromHead ? head.ends : tail.ends
        return MixEnds(
            intro: head.ends.intro,
            outro: tail.ends.outro,
            bpm: source.bpm,
            headBeat: refit(head, bpm: source.bpm, fallback: head.ends.headBeat),
            tailBeat: refit(tail, bpm: source.bpm, fallback: tail.ends.tailBeat),
            key: keySource.key,
            mode: keySource.mode
        )
    }
}
