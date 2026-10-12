import Foundation
import Observation
import UIKit
import NSMCore

@MainActor
@Observable
final class SiteSync {
    enum Phase: Equatable {
        case idle
        case loading
        case downloading
        case done
        case failed(String)
    }

    struct ListState: Identifiable, Equatable {
        let id: String
        var name: String
        var total: Int
        var done: Int
        var phase: Phase
    }

    private(set) var favorites = ListState(id: "favorites", name: "Понравившиеся", total: 0, done: 0, phase: .idle)
    private(set) var playlists: [ListState] = []
    private(set) var isRefreshing = false
    private(set) var needsLogin = false
    var lossless: Bool = UserDefaults.standard.object(forKey: "nsm_lossless") as? Bool ?? true

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let api = SiteAPI.shared
    @ObservationIgnored private weak var library: LibraryStore?
    @ObservationIgnored private var remotePlaylists: [String: SitePlaylist] = [:]
    @ObservationIgnored private var running = false

    init(database: AppDatabase, library: LibraryStore) {
        self.database = database
        self.library = library
    }

    func setLossless(_ value: Bool) {
        lossless = value
        UserDefaults.standard.set(value, forKey: "nsm_lossless")
    }

    func refresh() async {
        isRefreshing = true
        needsLogin = false
        defer { isRefreshing = false }
        do {
            async let likes = api.favorites()
            async let lists = api.playlists()
            let favoriteTracks = try await likes
            let remote = try await lists
            favorites.total = favoriteTracks.count
            favorites.done = alreadyHere(favoriteTracks)
            favorites.phase = favorites.done >= favorites.total && favorites.total > 0 ? .done : .idle
            remotePlaylists = Dictionary(uniqueKeysWithValues: remote.map { ($0.id.value, $0) })
            playlists = remote.map { item in
                ListState(
                    id: item.id.value,
                    name: item.name,
                    total: item.trackCount ?? 0,
                    done: 0,
                    phase: .idle
                )
            }
        } catch SiteError.unauthorized {
            needsLogin = true
        } catch SiteError.noToken {
            needsLogin = true
        } catch {
            favorites.phase = .failed("Не получилось загрузить список")
        }
    }

    private func alreadyHere(_ tracks: [SiteTrack]) -> Int {
        let known = Set((library?.tracks ?? []).compactMap { $0.siteId })
        return tracks.filter { known.contains($0.id.value) }.count
    }

    func downloadFavorites() async {
        guard !running else { return }
        running = true
        defer { running = false }
        favorites.phase = .loading
        do {
            let remote = try await api.favorites()
            favorites.total = remote.count
            favorites.done = 0
            favorites.phase = .downloading
            let ids = await ingest(remote) { [weak self] done in
                self?.favorites.done = done
            }
            for id in ids {
                try? database.setFavorite(id: id, value: true)
            }
            favorites.phase = .done
        } catch {
            favorites.phase = .failed("Не получилось скачать")
        }
    }

    func downloadPlaylist(_ id: String) async {
        guard !running, let position = playlists.firstIndex(where: { $0.id == id }) else { return }
        running = true
        defer { running = false }
        playlists[position].phase = .loading
        do {
            let detail = try await api.playlist(id)
            let remote = detail.tracks.sorted { $0.position < $1.position }.map { $0.track }
            playlists[position].total = remote.count
            playlists[position].done = 0
            playlists[position].phase = .downloading
            let ids = await ingest(remote) { [weak self] done in
                guard let self, let index = self.playlists.firstIndex(where: { $0.id == id }) else { return }
                self.playlists[index].done = done
            }
            var coverName: String?
            if let cover = detail.coverFilename {
                let local = "site-" + cover
                let target = AppPaths.coverURL(local)
                if FileManager.default.fileExists(atPath: target.path) {
                    coverName = local
                } else if (try? await Net.download(api.coverURL(cover), to: target)) != nil {
                    coverName = local
                }
            }
            let record = PlaylistRecord(
                id: "site-\(id)",
                name: detail.name,
                coverName: coverName,
                siteId: id,
                createdAt: Date()
            )
            try? database.save(record, trackIDs: ids)
            if let index = playlists.firstIndex(where: { $0.id == id }) {
                playlists[index].phase = .done
            }
        } catch {
            if let index = playlists.firstIndex(where: { $0.id == id }) {
                playlists[index].phase = .failed("Не получилось скачать")
            }
        }
    }

    private func fingerprint(_ track: SiteTrack) -> TrackFingerprint {
        TrackFingerprint(
            id: "site-\(track.id.value)",
            artist: track.artist,
            title: track.title,
            durationMs: track.durationSeconds.map { Int($0 * 1000) },
            fileHash: nil,
            format: track.format ?? ""
        )
    }

    private func ingest(_ remote: [SiteTrack], progress: @escaping (Int) -> Void) async -> [String] {
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "nsm-site-download") {
            UIApplication.shared.endBackgroundTask(taskID)
        }
        defer {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }
        let current = library?.tracks ?? []
        var bySite: [String: String] = [:]
        for track in current {
            if let site = track.siteId {
                bySite[site] = track.id
            }
        }
        var index = DuplicateIndex(current.map {
            TrackFingerprint(
                id: $0.id,
                artist: $0.artist,
                title: $0.title,
                durationMs: $0.durationMs,
                fileHash: $0.fileHash,
                format: $0.format,
                bitrateKbps: $0.bitrateKbps
            )
        })
        var ids: [String] = []
        var done = 0
        for item in remote {
            if let existing = bySite[item.id.value] {
                ids.append(existing)
            } else if let match = index.matches(for: fingerprint(item)).first(where: { $0.kind == .sameTrack }) {
                try? database.linkSite(trackID: match.existingID, siteID: item.id.value)
                bySite[item.id.value] = match.existingID
                ids.append(match.existingID)
            } else if let saved = try? await download(item) {
                bySite[item.id.value] = saved.id
                index.add(TrackFingerprint(
                    id: saved.id,
                    artist: saved.artist,
                    title: saved.title,
                    durationMs: saved.durationMs,
                    fileHash: saved.fileHash,
                    format: saved.format
                ))
                ids.append(saved.id)
            }
            done += 1
            progress(done)
        }
        return ids
    }

    private func download(_ remote: SiteTrack) async throws -> TrackRecord {
        let url = api.audioURL(remote, lossless: lossless)
        let ext = url.pathExtension.lowercased()
        let id = UUID().uuidString
        let fileName = "\(id).\(ext)"
        let destination = AppPaths.trackURL(fileName)
        let (temporary, response) = try await Net.session.download(for: Net.request(url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetError.invalid
        }
        let copied = try await Task.detached(priority: .utility) {
            try FileHasher.copyAndHash(from: temporary, to: destination)
        }.value
        try? FileManager.default.removeItem(at: temporary)

        var coverName: String?
        if let cover = remote.coverFilename {
            let local = "site-" + cover
            let target = AppPaths.coverURL(local)
            if FileManager.default.fileExists(atPath: target.path) {
                coverName = local
            } else if (try? await Net.download(api.coverURL(cover), to: target)) != nil {
                coverName = local
            }
        }
        var motionName: String?
        if let motion = remote.motionFilename {
            let local = "site-" + motion
            let target = AppPaths.motionURL(local)
            if FileManager.default.fileExists(atPath: target.path) {
                motionName = local
            } else if (try? await Net.download(api.motionURL(motion), to: target)) != nil {
                motionName = local
            }
        }
        let tags = await Task.detached(priority: .utility) { TagIO.read(destination) }.value

        var track = TrackRecord.blank(id: id)
        track.title = remote.title
        track.artist = remote.artist
        track.album = remote.album
        track.trackNumber = tags?.trackNumber
        track.discNumber = tags?.discNumber
        track.year = tags?.year
        track.genre = tags?.genre
        let seconds = remote.durationSeconds ?? tags?.duration ?? 0
        track.durationMs = Int((seconds * 1000).rounded())
        track.format = (remote.format ?? ext).lowercased()
        track.bitrateKbps = tags?.bitrateKbps
        track.sampleRate = tags?.sampleRate
        track.bitDepth = tags?.bitDepth
        track.fileName = fileName
        track.fileSize = copied.size
        track.fileHash = copied.hash
        track.coverName = coverName
        track.motionName = motionName
        track.siteId = remote.id.value
        try database.save(track)

        if let lyrics = await api.lyrics(remote.id.value) {
            if let synced = lyrics.synced, !synced.isEmpty {
                try? database.save(LyricsRecord(trackId: id, kind: "line", source: lyrics.source ?? "site", lrc: synced, plain: lyrics.plain, checkedAt: Date()))
            } else if let plain = lyrics.plain, !plain.isEmpty {
                try? database.save(LyricsRecord(trackId: id, kind: "plain", source: lyrics.source ?? "site", lrc: nil, plain: plain, checkedAt: Date()))
            }
        }
        return track
    }
}
