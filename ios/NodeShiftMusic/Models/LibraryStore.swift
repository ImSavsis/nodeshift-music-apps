import Foundation
import GRDB
import Observation

enum LibrarySort: String, CaseIterable, Sendable {
    case newest
    case popular
    case title

    var label: String {
        switch self {
        case .newest: return "Новые"
        case .popular: return "Популярные"
        case .title: return "По названию"
        }
    }
}

enum FormatFilter: String, CaseIterable, Sendable {
    case all
    case flac
    case mp3

    var label: String {
        switch self {
        case .all: return "Все"
        case .flac: return "FLAC"
        case .mp3: return "MP3"
        }
    }
}

enum LibraryViewMode: String, Sendable {
    case grid
    case list
}

@MainActor
@Observable
final class LibraryStore {
    var tracks: [TrackRecord] = []
    var playlists: [PlaylistRecord] = []
    var query = ""
    var sort: LibrarySort = .newest
    var formatFilter: FormatFilter = .all
    var viewMode: LibraryViewMode = .grid
    var menuTrack: TrackRecord?
    private(set) var loaded = false

    @ObservationIgnored private var database: AppDatabase?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var playlistObservation: Task<Void, Never>?

    init() {
        viewMode = LibraryViewMode(rawValue: UserDefaults.standard.string(forKey: "nsm_view") ?? "") ?? .grid
    }

    func attach(_ database: AppDatabase) {
        self.database = database
        observation?.cancel()
        observation = Task { [weak self] in
            let stream = ValueObservation
                .tracking { db in try TrackRecord.fetchAll(db) }
                .values(in: database.queue)
            do {
                for try await list in stream {
                    self?.tracks = list
                    self?.loaded = true
                }
            } catch {
                self?.loaded = true
            }
        }
        playlistObservation?.cancel()
        playlistObservation = Task { [weak self] in
            let stream = ValueObservation
                .tracking { db in try PlaylistRecord.order(Column("createdAt").desc).fetchAll(db) }
                .values(in: database.queue)
            do {
                for try await list in stream {
                    self?.playlists = list
                }
            } catch {}
        }
    }

    func tracks(in playlist: PlaylistRecord) -> [TrackRecord] {
        let ids = (try? database?.trackIDs(playlist: playlist.id)) ?? []
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    func deletePlaylist(_ playlist: PlaylistRecord) {
        try? database?.deletePlaylist(id: playlist.id)
    }

    func changeViewMode(_ mode: LibraryViewMode) {
        viewMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "nsm_view")
    }

    var filtered: [TrackRecord] {
        var list = tracks
        switch formatFilter {
        case .all: break
        case .flac: list = list.filter { $0.format.lowercased() == "flac" }
        case .mp3: list = list.filter { $0.format.lowercased() == "mp3" }
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            list = list.filter {
                $0.title.localizedStandardContains(needle)
                    || $0.artist.localizedStandardContains(needle)
                    || ($0.album ?? "").localizedStandardContains(needle)
            }
        }
        switch sort {
        case .newest:
            list.sort { $0.addedAt > $1.addedAt }
        case .popular:
            list.sort { $0.playCount > $1.playCount }
        case .title:
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return list
    }

    var recent: [TrackRecord] {
        tracks
            .filter { $0.lastPlayedAt != nil }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            .prefix(12)
            .map { $0 }
    }

    var favorites: [TrackRecord] {
        tracks.filter { $0.isFavorite }.sorted { $0.addedAt > $1.addedAt }
    }

    func track(id: String) -> TrackRecord? {
        tracks.first { $0.id == id }
    }

    func toggleFavorite(_ id: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        let value = !tracks[index].isFavorite
        if let database {
            try? database.setFavorite(id: id, value: value)
        } else {
            tracks[index].isFavorite = value
        }
    }

    func markPlayed(_ id: String) {
        if let database {
            try? database.markPlayed(id: id, at: Date())
        } else if let index = tracks.firstIndex(where: { $0.id == id }) {
            tracks[index].lastPlayedAt = Date()
            tracks[index].playCount += 1
        }
    }

    func delete(_ track: TrackRecord) {
        try? FileManager.default.removeItem(at: track.fileURL)
        let others = tracks.filter { $0.id != track.id }
        if let cover = track.coverName, !others.contains(where: { $0.coverName == cover }) {
            try? FileManager.default.removeItem(at: AppPaths.coverURL(cover))
        }
        if let motion = track.motionName, !others.contains(where: { $0.motionName == motion }) {
            try? FileManager.default.removeItem(at: AppPaths.motionURL(motion))
        }
        if let database {
            try? database.deleteTrack(id: track.id)
        } else {
            tracks.removeAll { $0.id == track.id }
        }
    }
}
