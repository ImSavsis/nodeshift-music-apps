import AVFoundation
import CoreMedia
import Foundation
import NSMCore

@MainActor
final class AutoMixAnalyzer {
    static let shared = AutoMixAnalyzer()

    private static let decodeCap: Int64 = 48 * 1024 * 1024
    private static let maxCached = 200
    private static let sampleRate = 11025.0

    private var ready: [String: MixEnds] = [:]
    private var pending: [String: Task<MixEnds, Never>] = [:]
    private var order: [String] = []

    func cached(id: String) -> MixEnds? {
        ready[id]
    }

    func ends(for track: TrackRecord, duration: Double) -> MixEnds {
        if let known = ready[track.id] {
            if known.bpm > 0 {
                return known
            }
            if let tagged = track.bpm, tagged > 0 {
                var patched = known
                patched.bpm = Double(tagged)
                return patched
            }
            return known
        }
        return AutoMix.heuristicEnds(duration: duration, taggedBpm: track.bpm.map(Double.init))
    }

    func study(_ track: TrackRecord, duration: Double) {
        if ready[track.id] != nil || pending[track.id] != nil {
            return
        }
        if track.isDolbyAtmos {
            return
        }
        let fallback = AutoMix.heuristicEnds(duration: duration, taggedBpm: track.bpm.map(Double.init))
        guard let url = analysisURL(for: track) else {
            store(fallback, for: track.id)
            return
        }
        let id = track.id
        let task = Task<MixEnds, Never> { [weak self] in
            let result = await Task.detached(priority: .utility) {
                await Self.analyze(url: url, fallbackDuration: duration, fallback: fallback)
            }.value
            self?.finish(id: id, ends: result)
            return result
        }
        pending[id] = task
    }

    private func finish(id: String, ends: MixEnds) {
        pending.removeValue(forKey: id)
        store(ends, for: id)
    }

    private func store(_ ends: MixEnds, for id: String) {
        if ready[id] == nil {
            order.append(id)
        }
        ready[id] = ends
        while order.count > Self.maxCached {
            let oldest = order.removeFirst()
            ready.removeValue(forKey: oldest)
        }
    }

    private func analysisURL(for track: TrackRecord) -> URL? {
        if track.isLocked {
            guard let site = track.siteId else { return nil }
            let kind = track.fileName.hasSuffix(".nlac") ? "lossless" : "lossy"
            return LockedMediaServer.shared.url("file/\(site)/\(kind)/\(track.fileName)")
        }
        if !track.isRemote {
            let local = track.fileURL
            return FileManager.default.fileExists(atPath: local.path) ? local : nil
        }
        if let site = track.siteId, let url = LockedMediaServer.shared.url("site/\(site)/lossy") {
            return url
        }
        return track.streamURL ?? track.losslessURL
    }

    nonisolated private static func extensionFor(mime: String?, url: URL) -> String {
        switch (mime ?? "").lowercased() {
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/mp4", "audio/aac", "audio/x-m4a", "audio/m4a": return "m4a"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        case "audio/aiff", "audio/x-aiff": return "aif"
        default:
            let ext = url.pathExtension.lowercased()
            return ext.isEmpty ? "mp3" : ext
        }
    }

    nonisolated private static func analyze(url: URL, fallbackDuration: Double, fallback: MixEnds) async -> MixEnds {
        if url.isFileURL {
            return (try? await decodeFile(url, fallbackDuration: fallbackDuration)) ?? fallback
        }
        guard let (downloaded, response) = try? await URLSession.shared.download(from: url) else {
            return fallback
        }
        let fm = FileManager.default
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? fm.removeItem(at: downloaded)
            return fallback
        }
        if response.expectedContentLength > decodeCap {
            try? fm.removeItem(at: downloaded)
            return fallback
        }
        if let attrs = try? fm.attributesOfItem(atPath: downloaded.path),
           let size = attrs[.size] as? NSNumber,
           size.int64Value > decodeCap {
            try? fm.removeItem(at: downloaded)
            return fallback
        }
        let ext = extensionFor(mime: response.mimeType, url: response.url ?? url)
        let staged = fm.temporaryDirectory.appendingPathComponent("nsm-mix-\(UUID().uuidString).\(ext)")
        do {
            try fm.moveItem(at: downloaded, to: staged)
        } catch {
            try? fm.removeItem(at: downloaded)
            return fallback
        }
        defer { try? fm.removeItem(at: staged) }
        return (try? await decodeFile(staged, fallbackDuration: fallbackDuration)) ?? fallback
    }

    nonisolated private static func decodeFile(_ fileURL: URL, fallbackDuration: Double) async throws -> MixEnds {
        let rate = sampleRate
        let asset = AVURLAsset(url: fileURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CancellationError()
        }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw CancellationError()
        }
        reader.add(output)
        guard reader.startReading() else {
            throw CancellationError()
        }

        let headCap = Int(AutoMix.headSeconds * rate)
        let tailCap = Int(AutoMix.tailSeconds * rate)
        var head: [Float] = []
        head.reserveCapacity(headCap)
        var tailRing = [Float](repeating: 0, count: tailCap)
        var tailCursor = 0
        var totalSamples = 0
        var scratch: [Float] = []

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let totalLength = CMBlockBufferGetDataLength(blockBuffer)
            guard totalLength >= MemoryLayout<Float>.size else { continue }
            let count = totalLength / MemoryLayout<Float>.size
            if scratch.count < count {
                scratch = [Float](repeating: 0, count: count)
            }
            let copyStatus = scratch.withUnsafeMutableBytes { dst -> OSStatus in
                guard let base = dst.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: count * MemoryLayout<Float>.size,
                    destination: base
                )
            }
            guard copyStatus == kCMBlockBufferNoErr else { continue }
            if head.count < headCap {
                let take = min(count, headCap - head.count)
                head.append(contentsOf: scratch[0..<take])
            }
            if count >= tailCap {
                let offset = count - tailCap
                tailRing.replaceSubrange(0..<tailCap, with: scratch[offset..<(offset + tailCap)])
                tailCursor = 0
            } else {
                let first = min(count, tailCap - tailCursor)
                tailRing.replaceSubrange(tailCursor..<(tailCursor + first), with: scratch[0..<first])
                let second = count - first
                if second > 0 {
                    tailRing.replaceSubrange(0..<second, with: scratch[first..<(first + second)])
                }
                tailCursor = (tailCursor + count) % tailCap
            }
            totalSamples += count
        }

        guard totalSamples > 0 else {
            throw CancellationError()
        }

        let tail: [Float]
        if totalSamples <= tailCap {
            tail = Array(tailRing[0..<totalSamples])
        } else {
            var ordered: [Float] = []
            ordered.reserveCapacity(tailCap)
            ordered.append(contentsOf: tailRing[tailCursor..<tailCap])
            ordered.append(contentsOf: tailRing[0..<tailCursor])
            tail = ordered
        }

        let total = Double(totalSamples) / rate
        let fullDuration = total > 0 ? total : fallbackDuration
        let tailStart = max(0.0, Double(totalSamples - tail.count) / rate)
        let headRead = AutoMix.readRegion(
            samples: head,
            sampleRate: rate,
            region: .head,
            regionStart: 0,
            fullDuration: fullDuration
        )
        let tailRead = AutoMix.readRegion(
            samples: tail,
            sampleRate: rate,
            region: .tail,
            regionStart: tailStart,
            fullDuration: fullDuration
        )
        return AutoMix.mergeRegions(head: headRead, tail: tailRead)
    }
}
