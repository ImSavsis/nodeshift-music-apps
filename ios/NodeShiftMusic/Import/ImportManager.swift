import Foundation
import Observation
import UIKit
import NSMCore

struct ImportItem: Identifiable, Equatable {
    enum State: Equatable {
        case waiting
        case working(String)
        case done
        case duplicate(existingID: String, kind: String, betterQuality: Bool)
        case skipped(String)
        case failed(String)
    }

    let id: UUID
    var name: String
    var state: State
    var title: String?
    var artist: String?
    var coverName: String?
    var trackID: String?
}

enum DuplicateDecision {
    case skip
    case keepBoth
    case replace
}

struct ImportSummary: Equatable {
    var added = 0
    var duplicates = 0
    var failed = 0
    var ignored = 0
}

protocol CatalogProviding: Sendable {
    func lookup(_ query: CatalogQuery) async -> CatalogMatch?
    func downloadCover(_ url: URL) async -> Data?
}

struct NetworkCatalog: CatalogProviding {
    func lookup(_ query: CatalogQuery) async -> CatalogMatch? {
        await CatalogClient.lookup(query)
    }

    func downloadCover(_ url: URL) async -> Data? {
        try? await Net.data(url)
    }
}

private struct PendingDuplicate {
    var track: TrackRecord
    var tags: WriteTags
    var coverData: Data?
    var replacing: String
}

@MainActor
@Observable
final class ImportManager {
    private(set) var items: [ImportItem] = []
    private(set) var isRunning = false
    private(set) var summary = ImportSummary()

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let tracksDir: URL
    @ObservationIgnored private let coversDir: URL
    @ObservationIgnored private let scratchDir: URL
    @ObservationIgnored private let catalog: CatalogProviding?
    @ObservationIgnored private var index = DuplicateIndex()
    @ObservationIgnored private var pending: [UUID: PendingDuplicate] = [:]
    @ObservationIgnored private var albumCovers: [String: String] = [:]
    @ObservationIgnored var onTrackAdded: ((TrackRecord) -> Void)?
    @ObservationIgnored var onTrackRemoved: ((String) -> Void)?

    private static let dolbyCandidates: Set<String> = ["m4a", "mp4", "ec3", "eac3", "ac3", "caf"]

    init(
        database: AppDatabase,
        tracksDir: URL = AppPaths.tracksDir,
        coversDir: URL = AppPaths.coversDir,
        scratchDir: URL = AppPaths.scratchDir,
        catalog: CatalogProviding? = NetworkCatalog()
    ) {
        self.database = database
        self.tracksDir = tracksDir
        self.coversDir = coversDir
        self.scratchDir = scratchDir
        self.catalog = catalog
    }

    @discardableResult
    func add(urls: [URL]) -> Task<Void, Never> {
        if urls.isEmpty {
            return Task {}
        }
        return Task { await run(urls) }
    }

    func clearFinished() {
        items.removeAll { item in
            switch item.state {
            case .done, .skipped, .failed: return true
            default: return false
            }
        }
        if items.isEmpty {
            summary = ImportSummary()
        }
    }

    func decide(_ id: UUID, _ decision: DuplicateDecision) {
        guard let position = items.firstIndex(where: { $0.id == id }), let waiting = pending[id] else { return }
        pending[id] = nil
        switch decision {
        case .skip:
            discard(waiting.track)
            items[position].state = .skipped("Пропущен: уже есть")
            summary.duplicates += 1
        case .keepBoth:
            commit(waiting, at: position, replacing: nil)
        case .replace:
            commit(waiting, at: position, replacing: waiting.replacing)
        }
    }

    func skipAllDuplicates() {
        for id in Array(pending.keys) {
            decide(id, .skip)
        }
    }

    var pendingDuplicates: Int {
        pending.count
    }

    private func run(_ urls: [URL]) async {
        isRunning = true
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for url in scoped {
                url.stopAccessingSecurityScopedResource()
            }
            isRunning = false
        }
        let scratch = scratchDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scan = await Task.detached(priority: .userInitiated) {
            ImportScanner.scan(urls, scratch: scratch)
        }.value
        summary.ignored += scan.skipped
        await loadIndex()
        let grouped = Dictionary(grouping: scan.candidates, by: { $0.group })
        var parsedByURL: [URL: ParsedName] = [:]
        for (_, group) in grouped {
            let names = group.map { $0.url.lastPathComponent }
            let parsed = FilenameParser.parseBatch(names)
            for (candidate, result) in zip(group, parsed) {
                parsedByURL[candidate.url] = result
            }
        }
        var ids: [URL: UUID] = [:]
        for candidate in scan.candidates {
            let id = UUID()
            ids[candidate.url] = id
            let parsed = parsedByURL[candidate.url]
            items.append(ImportItem(
                id: id,
                name: candidate.url.lastPathComponent,
                state: .waiting,
                title: parsed?.title,
                artist: parsed?.artist,
                coverName: nil,
                trackID: nil
            ))
        }
        for candidate in scan.candidates {
            guard let id = ids[candidate.url] else { continue }
            await process(candidate, id: id, parsed: parsedByURL[candidate.url] ?? ParsedName())
        }
        try? FileManager.default.removeItem(at: scratch)
    }

    private func loadIndex() async {
        let database = self.database
        let tracks = (try? await Task.detached { try database.allTracks() }.value) ?? []
        index = DuplicateIndex(tracks.map(Self.fingerprint))
    }

    private static func fingerprint(_ track: TrackRecord) -> TrackFingerprint {
        TrackFingerprint(
            id: track.id,
            artist: track.artist,
            title: track.title,
            durationMs: track.durationMs,
            fileHash: track.fileHash,
            format: track.format,
            bitrateKbps: track.bitrateKbps
        )
    }

    private func update(_ id: UUID, _ change: (inout ImportItem) -> Void) {
        guard let position = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[position])
    }

    private func discard(_ track: TrackRecord) {
        try? FileManager.default.removeItem(at: tracksDir.appendingPathComponent(track.fileName))
        if let cover = track.coverName, !albumCovers.values.contains(cover) {
            try? FileManager.default.removeItem(at: coversDir.appendingPathComponent(cover))
        }
    }

    private func process(_ candidate: ImportCandidate, id: UUID, parsed: ParsedName) async {
        let ext = candidate.url.pathExtension.lowercased()
        let trackID = UUID().uuidString
        let fileName = "\(trackID).\(ext)"
        let destination = tracksDir.appendingPathComponent(fileName)
        update(id) { $0.state = .working("Копируем") }

        let source = candidate.url
        let copied: (hash: String, size: Int64)
        do {
            copied = try await Task.detached(priority: .userInitiated) {
                try FileHasher.copyAndHash(from: source, to: destination)
            }.value
        } catch {
            update(id) { $0.state = .failed("Не удалось скопировать") }
            summary.failed += 1
            return
        }

        if index.existingID(forHash: copied.hash) != nil {
            try? FileManager.default.removeItem(at: destination)
            update(id) { $0.state = .skipped("Уже есть в библиотеке") }
            summary.duplicates += 1
            return
        }

        update(id) { $0.state = .working("Читаем теги") }
        var dolby: AudioInspection?
        if Self.dolbyCandidates.contains(ext) {
            let found = await AudioInspector.inspect(destination)
            if found?.isDolby == true {
                dolby = found
            }
        }
        let readTags = await Task.detached(priority: .userInitiated, operation: { TagIO.read(destination) }).value
        guard let tags = readTags ?? dolby?.readTags else {
            try? FileManager.default.removeItem(at: destination)
            update(id) { $0.state = .failed("Формат не читается") }
            summary.failed += 1
            return
        }

        let stem = candidate.url.deletingPathExtension().lastPathComponent
        var title = tags.title ?? parsed.title ?? stem
        var artist = tags.artist ?? parsed.artist ?? ""
        var album = tags.album
        var albumArtist = tags.albumArtist
        var trackNumber = tags.trackNumber ?? parsed.track
        var discNumber = tags.discNumber ?? parsed.disc
        var year = tags.year
        var genre = tags.genre
        var isrc: String?
        var coverData = tags.cover
        let duration = tags.duration ?? 0

        if let catalog {
            update(id) { $0.state = .working("Ищем в каталоге") }
            let query = CatalogQuery(title: title, artist: artist, album: album, duration: duration > 0 ? duration : nil)
            if let match = await catalog.lookup(query) {
                if tags.title == nil || TextMatching.titleRatio(title, match.title) >= 0.95 {
                    title = match.title
                }
                if tags.artist == nil || artist.isEmpty || TextMatching.artistRatio(artist, match.artist) >= 0.95 {
                    artist = match.artist
                }
                album = album ?? match.album
                albumArtist = albumArtist ?? match.albumArtist
                trackNumber = trackNumber ?? match.trackNumber
                discNumber = discNumber ?? match.discNumber
                year = year ?? match.year
                genre = genre ?? match.genre
                isrc = match.isrc
                if coverData == nil, let url = match.coverURL {
                    coverData = await catalog.downloadCover(url)
                }
            }
        }

        if artist.isEmpty {
            artist = "Неизвестный исполнитель"
        }

        let albumKey = (album.map { artist.lowercased() + "|" + $0.lowercased() })
        var coverName: String?
        var jpeg: Data?
        if let albumKey, let known = albumCovers[albumKey] {
            coverName = known
        } else if let coverData {
            jpeg = Self.normalizedJPEG(coverData)
            if jpeg != nil {
                coverName = "\(UUID().uuidString).jpg"
            }
        }

        update(id) { $0.state = .working("Пишем теги") }
        let writeTags = WriteTags(
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            isrc: isrc,
            cover: jpeg
        )
        if dolby == nil {
            _ = try? await Task.detached(priority: .userInitiated) {
                try TagIO.write(destination, tags: writeTags)
            }.value
        }

        if let jpeg, let coverName {
            try? jpeg.write(to: coversDir.appendingPathComponent(coverName))
            if let albumKey {
                albumCovers[albumKey] = coverName
            }
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let finalSize = (attributes?[.size] as? Int64) ?? copied.size
        var track = TrackRecord.blank(id: trackID)
        track.title = title
        track.artist = artist
        track.album = album
        track.albumArtist = albumArtist
        track.trackNumber = trackNumber
        track.discNumber = discNumber
        track.year = year
        track.genre = genre
        track.durationMs = Int((duration * 1000).rounded())
        track.format = dolby?.formatName ?? ext
        track.bitrateKbps = tags.bitrateKbps
        track.sampleRate = tags.sampleRate
        track.bitDepth = tags.bitDepth
        track.fileName = fileName
        track.fileSize = finalSize
        track.fileHash = copied.hash
        track.coverName = coverName

        let duplicates = index.matches(for: Self.fingerprint(track))
        guard let position = items.firstIndex(where: { $0.id == id }) else { return }
        update(id) {
            $0.title = title
            $0.artist = artist
            $0.coverName = coverName
        }
        if let hit = duplicates.first(where: { $0.kind != .sameFile }) {
            pending[id] = PendingDuplicate(track: track, tags: writeTags, coverData: jpeg, replacing: hit.existingID)
            items[position].state = .duplicate(
                existingID: hit.existingID,
                kind: hit.kind.rawValue,
                betterQuality: hit.candidateIsBetterQuality
            )
            return
        }
        commit(PendingDuplicate(track: track, tags: writeTags, coverData: jpeg, replacing: ""), at: position, replacing: nil)
    }

    private func commit(_ pending: PendingDuplicate, at position: Int, replacing: String?) {
        if let replacing, !replacing.isEmpty {
            if let old = try? database.allTracks().first(where: { $0.id == replacing }) {
                try? FileManager.default.removeItem(at: tracksDir.appendingPathComponent(old.fileName))
            }
            try? database.deleteTrack(id: replacing)
            index.remove(id: replacing)
            onTrackRemoved?(replacing)
        }
        do {
            try database.save(pending.track)
        } catch {
            items[position].state = .failed("Не удалось сохранить")
            summary.failed += 1
            return
        }
        index.add(Self.fingerprint(pending.track))
        items[position].state = .done
        items[position].trackID = pending.track.id
        summary.added += 1
        onTrackAdded?(pending.track)
    }

    static func normalizedJPEG(_ data: Data, maxSide: CGFloat = 1400) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height) * image.scale
        if longest <= maxSide, let first = data.first, first == 0xFF {
            return data
        }
        let ratio = min(1, maxSide / max(longest, 1))
        let size = CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.9)
    }
}
