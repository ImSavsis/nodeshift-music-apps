import Foundation
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
    var query = ""
    var sort: LibrarySort = .newest
    var formatFilter: FormatFilter = .all
    var viewMode: LibraryViewMode = .grid
    var menuTrack: TrackRecord?

    init() {
        viewMode = LibraryViewMode(rawValue: UserDefaults.standard.string(forKey: "nsm_view") ?? "") ?? .grid
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
        tracks[index].isFavorite.toggle()
    }

    func markPlayed(_ id: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].lastPlayedAt = Date()
        tracks[index].playCount += 1
    }
}
