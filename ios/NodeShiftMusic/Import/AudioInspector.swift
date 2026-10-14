import AVFoundation
import CoreMedia
import Foundation

struct BitReader {
    private let bytes: [UInt8]
    private var position = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var remaining: Int {
        bytes.count * 8 - position
    }

    mutating func read(_ count: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        guard position + count <= bytes.count * 8 else {
            position = bytes.count * 8
            return 0
        }
        var value = 0
        for _ in 0..<count {
            let byte = bytes[position / 8]
            let bit = (byte >> (7 - UInt8(position % 8))) & 1
            value = (value << 1) | Int(bit)
            position += 1
        }
        return value
    }
}

enum Dec3Probe {
    static func isJOC(in data: Data) -> Bool {
        guard let marker = data.range(of: Data("dec3".utf8)), marker.lowerBound >= 4 else {
            return false
        }
        let start = marker.lowerBound - 4
        let size = Int(data[start]) << 24 | Int(data[start + 1]) << 16 | Int(data[start + 2]) << 8 | Int(data[start + 3])
        let payloadStart = marker.upperBound
        let payloadEnd = min(data.count, start + size)
        guard payloadEnd - payloadStart >= 5 else {
            return false
        }
        var reader = BitReader(bytes: Array(data[payloadStart..<payloadEnd]))
        _ = reader.read(13)
        let substreams = reader.read(3) + 1
        for _ in 0..<substreams {
            _ = reader.read(2)
            _ = reader.read(5)
            _ = reader.read(1)
            _ = reader.read(1)
            _ = reader.read(3)
            _ = reader.read(3)
            _ = reader.read(1)
            _ = reader.read(3)
            let dependent = reader.read(4)
            _ = reader.read(dependent > 0 ? 9 : 1)
        }
        guard reader.remaining >= 16 else {
            return false
        }
        _ = reader.read(7)
        let flag = reader.read(1)
        let complexity = reader.read(8)
        return flag == 1 && complexity > 0
    }

    static func isJOC(file url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else {
            return false
        }
        return isJOC(in: data)
    }
}

struct AudioInspection: Sendable {
    var codec: String
    var isEAC3: Bool
    var isAC3: Bool
    var isAtmos: Bool
    var channels: Int
    var sampleRate: Double
    var duration: Double
    var title: String?
    var artist: String?
    var album: String?
    var cover: Data?

    var isDolby: Bool {
        isEAC3 || isAC3
    }

    var formatName: String {
        if isAtmos {
            return "atmos"
        }
        return isEAC3 ? "eac3" : "ac3"
    }

    var readTags: ReadTags {
        var tags = ReadTags()
        tags.title = title
        tags.artist = artist
        tags.album = album
        tags.duration = duration > 0 ? duration : nil
        tags.sampleRate = sampleRate > 0 ? Int(sampleRate) : nil
        tags.formatName = codec
        tags.cover = cover
        return tags
    }
}

enum AudioInspector {
    static func inspect(_ url: URL) async -> AudioInspection? {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), let track = tracks.first else {
            return nil
        }
        let descriptions = (try? await track.load(.formatDescriptions)) ?? []
        var formatID: AudioFormatID = 0
        var channels = 0
        var sampleRate = 0.0
        if let description = descriptions.first, let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
            formatID = basic.mFormatID
            channels = Int(basic.mChannelsPerFrame)
            sampleRate = basic.mSampleRate
        }
        let isEAC3 = formatID == kAudioFormatEnhancedAC3
        let isAC3 = formatID == kAudioFormatAC3
        let atmos = isEAC3 && Dec3Probe.isJOC(file: url)
        let duration = ((try? await asset.load(.duration))?.seconds).flatMap { $0.isFinite ? $0 : nil } ?? 0

        var inspection = AudioInspection(
            codec: fourCC(formatID),
            isEAC3: isEAC3,
            isAC3: isAC3,
            isAtmos: atmos,
            channels: channels,
            sampleRate: sampleRate,
            duration: duration
        )
        if isEAC3 || isAC3 {
            await fillMetadata(&inspection, asset: asset)
        }
        return inspection
    }

    private static func fillMetadata(_ inspection: inout AudioInspection, asset: AVURLAsset) async {
        guard let items = try? await asset.load(.commonMetadata) else {
            return
        }
        for item in items {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle:
                inspection.title = try? await item.load(.stringValue)
            case .commonKeyArtist:
                inspection.artist = try? await item.load(.stringValue)
            case .commonKeyAlbumName:
                inspection.album = try? await item.load(.stringValue)
            case .commonKeyArtwork:
                inspection.cover = try? await item.load(.dataValue)
            default:
                break
            }
        }
    }

    private static func fourCC(_ value: AudioFormatID) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "?"
    }
}
