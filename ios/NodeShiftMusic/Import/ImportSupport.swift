import CryptoKit
import Foundation
import SFBAudioEngine
import SWCompression
import ZIPFoundation

enum FileHasher {
    static func copyAndHash(from source: URL, to destination: URL) throws -> (hash: String, size: Int64) {
        let manager = FileManager.default
        try? manager.removeItem(at: destination)
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        manager.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }
        var hasher = SHA256()
        var total: Int64 = 0
        while true {
            let chunk = try input.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
            try output.write(contentsOf: chunk)
            total += Int64(chunk.count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (digest, total)
    }

    static func hash(of url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hasher = SHA256()
        while true {
            let chunk = try input.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum ArchiveExtractor {
    static let archiveExtensions: Set<String> = ["zip", "7z"]

    static func isArchive(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }

    static func sanitize(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .filter { $0 != ".." && $0 != "." && !$0.isEmpty }
            .joined(separator: "/")
    }

    static func extract(_ archive: URL, into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        switch archive.pathExtension.lowercased() {
        case "zip":
            try FileManager.default.unzipItem(at: archive, to: directory)
        case "7z":
            let data = try Data(contentsOf: archive, options: .mappedIfSafe)
            let entries = try SevenZipContainer.open(container: data)
            for entry in entries where entry.info.type == .regular {
                guard let content = entry.data else { continue }
                let safe = sanitize(entry.info.name)
                if safe.isEmpty {
                    continue
                }
                let target = directory.appendingPathComponent(safe)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: target)
            }
        default:
            break
        }
    }
}

struct ImportCandidate: Sendable {
    let url: URL
    let group: String
}

enum ImportScanner {
    static let trackerFormats: Set<String> = ["mod", "s3m", "xm", "it"]

    static var audioExtensions: Set<String> {
        Set(AudioFile.supportedPathExtensions.map { $0.lowercased() })
            .subtracting(trackerFormats)
            .union(AudioFormats.systemDecodedExtensions)
    }

    static func scan(_ roots: [URL], scratch: URL) -> (candidates: [ImportCandidate], skipped: Int) {
        let extensions = audioExtensions
        var candidates: [ImportCandidate] = []
        var skipped = 0
        let manager = FileManager.default

        func visit(_ url: URL, group: String) {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
            if isDirectory.boolValue {
                let children = (try? manager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
                for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    visit(child, group: url.path)
                }
                return
            }
            let ext = url.pathExtension.lowercased()
            if ArchiveExtractor.isArchive(url) {
                let target = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
                do {
                    try ArchiveExtractor.extract(url, into: target)
                    visit(target, group: target.path)
                } catch {
                    skipped += 1
                }
            } else if extensions.contains(ext) {
                candidates.append(ImportCandidate(url: url, group: group))
            } else {
                skipped += 1
            }
        }

        for root in roots {
            visit(root, group: root.deletingLastPathComponent().path)
        }
        return (candidates, skipped)
    }
}

struct ReadTags: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genre: String?
    var trackNumber: Int?
    var discNumber: Int?
    var year: Int?
    var duration: Double?
    var sampleRate: Int?
    var bitDepth: Int?
    var bitrateKbps: Int?
    var formatName: String?
    var cover: Data?
    var lyrics: String?
}

struct WriteTags: Sendable {
    var title: String
    var artist: String
    var album: String?
    var albumArtist: String?
    var genre: String?
    var trackNumber: Int?
    var discNumber: Int?
    var year: Int?
    var isrc: String?
    var cover: Data?
}

enum TagIO {
    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func read(_ url: URL) -> ReadTags? {
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url) else { return nil }
        let metadata = file.metadata
        let properties = file.properties
        var tags = ReadTags()
        tags.title = clean(metadata.title)
        tags.artist = clean(metadata.artist)
        tags.album = clean(metadata.albumTitle)
        tags.albumArtist = clean(metadata.albumArtist)
        tags.genre = clean(metadata.genre)
        tags.trackNumber = metadata.trackNumber
        tags.discNumber = metadata.discNumber
        if let date = clean(metadata.releaseDate), date.count >= 4 {
            tags.year = Int(date.prefix(4))
        }
        tags.duration = properties.duration
        tags.sampleRate = properties.sampleRate.map { Int($0) }
        tags.bitDepth = properties.bitDepth
        tags.bitrateKbps = properties.bitrate.map { Int($0.rounded()) }
        tags.formatName = properties.formatName
        tags.lyrics = clean(metadata.lyrics)
        let pictures = Array(metadata.attachedPictures)
        if let front = pictures.first(where: { $0.type == .frontCover }) ?? pictures.first {
            tags.cover = front.imageData
        }
        return tags
    }

    static func write(_ url: URL, tags: WriteTags) throws {
        let file = try AudioFile(readingPropertiesAndMetadataFrom: url)
        let metadata = file.metadata
        metadata.title = tags.title
        metadata.artist = tags.artist
        if let album = tags.album {
            metadata.albumTitle = album
        }
        if let albumArtist = tags.albumArtist {
            metadata.albumArtist = albumArtist
        }
        if let genre = tags.genre {
            metadata.genre = genre
        }
        if let number = tags.trackNumber {
            metadata.trackNumber = number
        }
        if let disc = tags.discNumber {
            metadata.discNumber = disc
        }
        if let year = tags.year {
            metadata.releaseDate = String(year)
        }
        if let isrc = tags.isrc {
            metadata.isrc = isrc
        }
        if let cover = tags.cover {
            metadata.removeAttachedPicturesOfType(.frontCover)
            metadata.attachPicture(AttachedPicture(imageData: cover, type: .frontCover))
        }
        try file.writeMetadata()
    }
}
