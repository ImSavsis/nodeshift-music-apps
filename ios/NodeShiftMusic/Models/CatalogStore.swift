import Foundation
import Observation

extension SiteTrack {
    func catalogRecord(api: SiteAPI = .shared) -> TrackRecord {
        var record = TrackRecord.blank(id: "site:\(id.value)")
        record.title = title
        record.artist = artist
        record.album = album
        record.durationMs = Int((durationSeconds ?? 0) * 1000)
        record.format = (format ?? "mp3").lowercased()
        record.coverName = coverFilename.map { CoverSource.remoteName($0) }
        record.siteId = id.value
        record.playCount = playCount ?? 0
        record.streamURL = api.audioURL(self, lossless: false)
        return record
    }
}

@MainActor
@Observable
final class CatalogStore {
    static let pageSize = 30

    var tracks: [TrackRecord] = []
    var query = ""
    var sort: LibrarySort = .newest
    var formatFilter: FormatFilter = .all
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var failed = false
    private(set) var likedIDs: Set<String> = []

    @ObservationIgnored private var offset = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private weak var library: LibraryStore?
    @ObservationIgnored private weak var site: SiteSession?
    @ObservationIgnored private weak var toasts: ToastCenter?

    func attach(library: LibraryStore, site: SiteSession, toasts: ToastCenter) {
        self.library = library
        self.site = site
        self.toasts = toasts
    }

    private var apiSort: String {
        switch sort {
        case .newest: return "new"
        case .popular: return "popular"
        case .title: return "title"
        }
    }

    func startIfNeeded() {
        if tracks.isEmpty, !isLoading {
            reload()
        }
    }

    func queryChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func reload() {
        generation += 1
        offset = 0
        hasMore = true
        load(reset: true)
    }

    func loadMore() {
        guard hasMore, !isLoading else { return }
        load(reset: false)
    }

    private func record(for item: SiteTrack) -> TrackRecord {
        if let local = library?.tracks.first(where: { $0.siteId == item.id.value }) {
            return local
        }
        return item.catalogRecord()
    }

    private func load(reset: Bool) {
        let token = generation
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortKey = apiSort
        let format: String? = formatFilter == .all ? nil : formatFilter.rawValue
        let start = offset
        isLoading = true
        failed = false
        Task { [weak self] in
            do {
                let page = try await SiteAPI.shared.catalog(
                    search: needle,
                    sort: sortKey,
                    format: format,
                    limit: CatalogStore.pageSize,
                    offset: start
                )
                guard let self, token == self.generation else { return }
                let playable = page.filter { $0.mediaKind != "video" }
                let mapped = playable.map { self.record(for: $0) }
                if reset {
                    self.tracks = mapped
                } else {
                    let known = Set(self.tracks.map { $0.id })
                    self.tracks.append(contentsOf: mapped.filter { !known.contains($0.id) })
                }
                self.offset = start + page.count
                self.hasMore = page.count == CatalogStore.pageSize
                self.isLoading = false
            } catch {
                guard let self, token == self.generation else { return }
                self.failed = true
                self.hasMore = false
                self.isLoading = false
            }
        }
    }

    func wave() async -> [TrackRecord] {
        guard let page = try? await SiteAPI.shared.wave(limit: 40) else {
            toasts?.show("Не получилось запустить волну")
            return []
        }
        return page.map { record(for: $0) }
    }

    func refreshLikes() async {
        guard site?.isLoggedIn == true else {
            likedIDs = []
            return
        }
        if let ids = try? await SiteAPI.shared.likedIDs() {
            likedIDs = ids
        }
    }

    func clearLikes() {
        likedIDs = []
    }

    func isFavorite(_ track: TrackRecord) -> Bool {
        if let siteID = track.siteId, track.isRemote {
            return likedIDs.contains(siteID)
        }
        return track.isFavorite
    }

    func toggleFavorite(_ track: TrackRecord, library: LibraryStore) {
        guard track.isRemote, let siteID = track.siteId else {
            library.toggleFavorite(track.id)
            return
        }
        guard site?.isLoggedIn == true else {
            toasts?.show("Войди через сайт, чтобы ставить лайки")
            return
        }
        let value = !likedIDs.contains(siteID)
        if value {
            likedIDs.insert(siteID)
        } else {
            likedIDs.remove(siteID)
        }
        Task { [weak self] in
            do {
                try await SiteAPI.shared.setLiked(siteID, value: value)
            } catch {
                guard let self else { return }
                if value {
                    self.likedIDs.remove(siteID)
                } else {
                    self.likedIDs.insert(siteID)
                }
                self.toasts?.show("Не получилось сохранить лайк")
            }
        }
    }
}
