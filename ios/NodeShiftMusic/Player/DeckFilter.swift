import AVFoundation
import CoreMedia
import Foundation
import MediaToolbox

struct DeckDSPState {
    var active: Int32 = 0
    var wasActive: Int32 = 0
    var supported: Int32 = 0
    var nonInterleaved: Int32 = 1
    var channels: Int32 = 2
    var sampleRate: Float = 44100
    var targetHz: Float = 18000
    var targetBassDb: Float = 0
    var curHz: Float = 18000
    var curBassDb: Float = 0
    var lastHz: Float = 18000
    var lastBassDb: Float = 0
    var coeffsReady: Int32 = 0

    var lpB0: Float = 1
    var lpB1: Float = 0
    var lpB2: Float = 0
    var lpA1: Float = 0
    var lpA2: Float = 0

    var lsB0: Float = 1
    var lsB1: Float = 0
    var lsB2: Float = 0
    var lsA1: Float = 0
    var lsA2: Float = 0

    var lsZ1L: Float = 0
    var lsZ2L: Float = 0
    var lsZ1R: Float = 0
    var lsZ2R: Float = 0
    var lpZ1L: Float = 0
    var lpZ2L: Float = 0
    var lpZ1R: Float = 0
    var lpZ2R: Float = 0

    mutating func resetDelays() {
        lsZ1L = 0
        lsZ2L = 0
        lsZ1R = 0
        lsZ2R = 0
        lpZ1L = 0
        lpZ2L = 0
        lpZ1R = 0
        lpZ2R = 0
    }

    mutating func recomputeCoeffs() {
        let fs = Double(sampleRate > 0 ? sampleRate : 44100)
        let maxFreq = fs * 0.45

        let lpFreq = min(maxFreq, max(80.0, Double(curHz)))
        let lpW0 = 2.0 * .pi * lpFreq / fs
        let lpCos = cos(lpW0)
        let lpSin = sin(lpW0)
        let lpAlpha = lpSin / (2.0 * 0.7)
        let lpA0 = 1.0 + lpAlpha
        lpB0 = Float(((1.0 - lpCos) * 0.5) / lpA0)
        lpB1 = Float((1.0 - lpCos) / lpA0)
        lpB2 = lpB0
        lpA1 = Float((-2.0 * lpCos) / lpA0)
        lpA2 = Float((1.0 - lpAlpha) / lpA0)

        let lsFreq = min(maxFreq, 140.0)
        let lsW0 = 2.0 * .pi * lsFreq / fs
        let lsCos = cos(lsW0)
        let lsSin = sin(lsW0)
        let a = pow(10.0, Double(curBassDb) / 40.0)
        let lsAlpha = lsSin * 0.5 * sqrt(2.0)
        let twoSqrtAAlpha = 2.0 * sqrt(a) * lsAlpha
        let lsA0 = (a + 1.0) + (a - 1.0) * lsCos + twoSqrtAAlpha
        lsB0 = Float((a * ((a + 1.0) - (a - 1.0) * lsCos + twoSqrtAAlpha)) / lsA0)
        lsB1 = Float((2.0 * a * ((a - 1.0) - (a + 1.0) * lsCos)) / lsA0)
        lsB2 = Float((a * ((a + 1.0) - (a - 1.0) * lsCos - twoSqrtAAlpha)) / lsA0)
        lsA1 = Float((-2.0 * ((a - 1.0) + (a + 1.0) * lsCos)) / lsA0)
        lsA2 = Float(((a + 1.0) + (a - 1.0) * lsCos - twoSqrtAAlpha) / lsA0)

        lastHz = curHz
        lastBassDb = curBassDb
        coeffsReady = 1
    }

    mutating func filterChannel(_ ptr: UnsafeMutablePointer<Float>, count: Int, stride: Int, right: Bool) {
        var s1 = right ? lsZ1R : lsZ1L
        var s2 = right ? lsZ2R : lsZ2L
        var p1 = right ? lpZ1R : lpZ1L
        var p2 = right ? lpZ2R : lpZ2L

        let sb0 = lsB0
        let sb1 = lsB1
        let sb2 = lsB2
        let sa1 = lsA1
        let sa2 = lsA2

        let pb0 = lpB0
        let pb1 = lpB1
        let pb2 = lpB2
        let pa1 = lpA1
        let pa2 = lpA2

        var idx = 0
        for _ in 0..<count {
            let x = ptr[idx]
            let y1 = sb0 * x + s1
            s1 = sb1 * x - sa1 * y1 + s2
            s2 = sb2 * x - sa2 * y1

            let y2 = pb0 * y1 + p1
            p1 = pb1 * y1 - pa1 * y2 + p2
            p2 = pb2 * y1 - pa2 * y2

            ptr[idx] = y2
            idx += stride
        }

        if abs(s1) < 1e-20 { s1 = 0 }
        if abs(s2) < 1e-20 { s2 = 0 }
        if abs(p1) < 1e-20 { p1 = 0 }
        if abs(p2) < 1e-20 { p2 = 0 }

        if right {
            lsZ1R = s1
            lsZ2R = s2
            lpZ1R = p1
            lpZ2R = p2
        } else {
            lsZ1L = s1
            lsZ2L = s2
            lpZ1L = p1
            lpZ2L = p2
        }
    }

    mutating func stepAndFilter(_ listPtr: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        if active == 0 {
            if wasActive != 0 {
                wasActive = 0
                resetDelays()
            }
            return
        }
        if wasActive == 0 {
            wasActive = 1
            curHz = targetHz
            curBassDb = targetBassDb
            coeffsReady = 0
            resetDelays()
        } else {
            curHz += (targetHz - curHz) * 0.25
            curBassDb += (targetBassDb - curBassDb) * 0.25
        }
        if coeffsReady == 0 || abs(curHz - lastHz) > 1.0 || abs(curBassDb - lastBassDb) > 0.05 {
            recomputeCoeffs()
        }
        let buffers = UnsafeMutableAudioBufferListPointer(listPtr)
        if nonInterleaved != 0 {
            let limit = min(2, buffers.count)
            for ch in 0..<limit {
                guard let raw = buffers[ch].mData else { continue }
                let available = Int(buffers[ch].mDataByteSize) / MemoryLayout<Float>.size
                let count = min(frames, available)
                if count <= 0 { continue }
                let samples = raw.assumingMemoryBound(to: Float.self)
                filterChannel(samples, count: count, stride: 1, right: ch == 1)
            }
        } else if let first = buffers.first, let raw = first.mData {
            let ch = Int(first.mNumberChannels)
            guard ch == 1 || ch == 2 else { return }
            let available = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * ch)
            let count = min(frames, available)
            if count <= 0 { return }
            let samples = raw.assumingMemoryBound(to: Float.self)
            filterChannel(samples, count: count, stride: ch, right: false)
            if ch == 2 {
                filterChannel(samples.advanced(by: 1), count: count, stride: 2, right: true)
            }
        }
    }
}

private struct TapContext {
    var dsp: UnsafeMutablePointer<DeckDSPState>
    var owner: Unmanaged<DeckFilter>
}

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    guard let clientInfo else { return }
    let owner = Unmanaged<DeckFilter>.fromOpaque(clientInfo)
    let ctx = UnsafeMutablePointer<TapContext>.allocate(capacity: 1)
    ctx.initialize(to: TapContext(dsp: owner.takeUnretainedValue().dsp, owner: owner))
    tapStorageOut.pointee = UnsafeMutableRawPointer(ctx)
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    let ctx = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: TapContext.self)
    ctx.pointee.owner.release()
    ctx.deinitialize(count: 1)
    ctx.deallocate()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, processingFormat in
    let ctx = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: TapContext.self)
    let dsp = ctx.pointee.dsp
    let format = processingFormat.pointee
    let isFloat = format.mFormatID == kAudioFormatLinearPCM
        && (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        && format.mBitsPerChannel == 32
    let channels = Int32(format.mChannelsPerFrame)
    dsp.pointee.supported = (isFloat && channels >= 1 && channels <= 2 && format.mSampleRate > 0) ? 1 : 0
    dsp.pointee.nonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0 ? 1 : 0
    dsp.pointee.channels = channels
    dsp.pointee.sampleRate = Float(format.mSampleRate > 0 ? format.mSampleRate : 44100)
    dsp.pointee.coeffsReady = 0
    dsp.pointee.resetDelays()
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
    let ctx = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: TapContext.self)
    ctx.pointee.dsp.pointee.resetDelays()
}

private let tapProcess: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }
    let ctx = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: TapContext.self)
    let dsp = ctx.pointee.dsp
    if (flagsOut.pointee & kMTAudioProcessingTapFlag_StartOfStream) != 0 {
        dsp.pointee.resetDelays()
    }
    guard dsp.pointee.supported != 0 else { return }
    let frames = Int(numberFramesOut.pointee)
    guard frames > 0 else { return }
    dsp.pointee.stepAndFilter(bufferListInOut, frames: frames)
}

final class DeckFilter: @unchecked Sendable {
    let dsp: UnsafeMutablePointer<DeckDSPState>

    init() {
        dsp = UnsafeMutablePointer<DeckDSPState>.allocate(capacity: 1)
        dsp.initialize(to: DeckDSPState())
    }

    deinit {
        dsp.deinitialize(count: 1)
        dsp.deallocate()
    }

    func update(active: Bool, hz: Float, bassDb: Float) {
        dsp.pointee.targetHz = max(80, min(18000, hz))
        dsp.pointee.targetBassDb = max(-24, min(6, bassDb))
        dsp.pointee.active = active ? 1 : 0
    }

    func bypass() {
        dsp.pointee.targetHz = 18000
        dsp.pointee.targetBassDb = 0
        dsp.pointee.active = 0
    }

    func makeAudioMix(for track: AVAssetTrack) -> AVAudioMix? {
        let retained = Unmanaged.passRetained(self).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: retained,
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )
        var created: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &created
        )
        guard status == noErr, let tap = created else {
            Unmanaged<DeckFilter>.fromOpaque(retained).release()
            return nil
        }
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        return mix
    }
}
