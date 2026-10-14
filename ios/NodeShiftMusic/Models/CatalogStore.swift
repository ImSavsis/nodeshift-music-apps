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
        record.motionName = motionFilename.map { CoverSource.remoteName($0) }
        record.siteId = id.value
        record.playCount = playCount ?? 0
        record.streamURL = api.audioURL(self, lossless: false)
        record.losslessURL = api.audioURL(self, lossless: true)
        return record
    }
}

@MainActor
@Observable
final class CatalogStore {
    static let pageSize = 60
    static let prefetchLimit = 1500

    var tracks: [TrackRecord] = []
    var query = ""
    var sort: LibrarySort = .newest
    var formatFilter: FormatFilter = .all
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var failed = false
    private(set) var likedIDs: Set<String> = []
    private(set) var wishlistIDs: Set<String> = []

    @ObservationIgnored private var offset = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
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
        prefetchTask?.cancel()
        Task { [weak self] in
            await self?.fetchPage(reset: true)
        }
    }

    func loadMore() {
        guard hasMore, !isLoading else { return }
        Task { [weak self] in
            await self?.fetchPage(reset: false)
        }
    }

    func record(for item: SiteTrack) -> TrackRecord {
        if let local = library?.tracks.first(where: { $0.siteId == item.id.value }) {
            return local
        }
        return item.catalogRecord()
    }

    private func fetchPage(reset: Bool) async {
        let token = generation
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortKey = apiSort
        let format: String? = formatFilter == .all ? nil : formatFilter.rawValue
        let start = offset
        isLoading = true
        failed = false
        do {
            let page = try await SiteAPI.shared.catalog(
                search: needle,
                sort: sortKey,
                format: format,
                limit: CatalogStore.pageSize,
                offset: start
            )
            guard token == generation else { return }
            let playable = page.filter { $0.mediaKind != "video" }
            let mapped = playable.map { record(for: $0) }
            if reset {
                tracks = mapped
            } else {
                let known = Set(tracks.map { $0.id })
                tracks.append(contentsOf: mapped.filter { !known.contains($0.id) })
            }
            propagateAlbumMotion()
            offset = start + page.count
            hasMore = page.count == CatalogStore.pageSize
            isLoading = false
            if reset {
                startPrefetch(token)
            }
        } catch {
            guard token == generation else { return }
            failed = tracks.isEmpty
            hasMore = false
            isLoading = false
        }
    }

    private func startPrefetch(_ token: Int) {
        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            while let self, !Task.isCancelled, token == self.generation, self.hasMore, self.tracks.count < CatalogStore.prefetchLimit {
                if self.isLoading {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    continue
                }
                await self.fetchPage(reset: false)
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func propagateAlbumMotion() {
        var byAlbum: [String: String] = [:]
        for track in tracks where track.isRemote {
            if let motion = track.motionName, let key = EnrichmentService.albumKey(track) {
                byAlbum[key] = motion
            }
        }
        guard !byAlbum.isEmpty else { return }
        for index in tracks.indices where tracks[index].isRemote && tracks[index].motionName == nil {
            if let key = EnrichmentService.albumKey(tracks[index]), let motion = byAlbum[key] {
                tracks[index].motionName = motion
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
            wishlistIDs = []
            return
        }
        if let state = try? await SiteAPI.shared.libraryState() {
            likedIDs = state.favorites
            wishlistIDs = state.wishlist
        }
    }

    func clearLikes() {
        likedIDs = []
        wishlistIDs = []
    }

    func isFavorite(_ track: TrackRecord) -> Bool {
        if let siteID = track.siteId, track.isRemote {
            return likedIDs.contains(siteID)
        }
        return track.isFavorite
    }

    func isWishlisted(_ track: TrackRecord) -> Bool {
        guard let siteID = track.siteId else { return false }
        return wishlistIDs.contains(siteID)
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

    func toggleWishlist(_ track: TrackRecord) {
        guard let siteID = track.siteId else {
            toasts?.show("Этого трека нет на сайте")
            return
        }
        guard site?.isLoggedIn == true else {
            toasts?.show("Войди через сайт, чтобы пользоваться вишлистом")
            return
        }
        let value = !wishlistIDs.contains(siteID)
        if value {
            wishlistIDs.insert(siteID)
        } else {
            wishlistIDs.remove(siteID)
        }
        toasts?.show(value ? "Добавлено в вишлист" : "Убрано из вишлиста")
        Task { [weak self] in
            do {
                try await SiteAPI.shared.setWishlisted(siteID, value: value)
            } catch {
                guard let self else { return }
                if value {
                    self.wishlistIDs.remove(siteID)
                } else {
                    self.wishlistIDs.insert(siteID)
                }
                self.toasts?.show("Не получилось сохранить вишлист")
            }
        }
    }
}
