import CryptoKit
import Foundation
import NSMCore
import Observation

@MainActor
@Observable
final class EnrichmentService {
    private(set) var libraryRunning = false
    private(set) var libraryDone = 0
    private(set) var libraryTotal = 0
    private(set) var libraryFound = 0

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let lyrics: LyricsStore
    @ObservationIgnored private var queue: [TrackRecord] = []
    @ObservationIgnored private var running = false
    @ObservationIgnored private var albumsDone: Set<String> = []

    init(database: AppDatabase, lyrics: LyricsStore) {
        self.database = database
        self.lyrics = lyrics
    }

    static var motionEnabled: Bool {
        UserDefaults.standard.object(forKey: "nsm_motion_auto") as? Bool ?? true
    }

    static func albumKey(_ track: TrackRecord) -> String? {
        guard let album = track.album, !album.isEmpty else { return nil }
        let artist = track.albumArtist ?? track.artist
        return TextMatching.artistKey(artist) + "|" + TextMatching.normalize(album)
    }

    private static func fileKey(_ albumKey: String) -> String {
        let digest = SHA256.hash(data: Data(albumKey.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func enqueue(_ track: TrackRecord) {
        queue.append(track)
        if !running {
            running = true
            Task { await drain() }
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            let track = queue.removeFirst()
            await lyrics.ensure(track)
            await findMotion(for: track, force: false)
        }
        running = false
    }

    private func checkedRecently(_ key: String, days: Double) -> Bool {
        let checks = UserDefaults.standard.dictionary(forKey: "nsm_motion_checked") as? [String: Double] ?? [:]
        guard let stamp = checks[key] else { return false }
        return Date().timeIntervalSince1970 - stamp < days * 86_400
    }

    private func markChecked(_ key: String) {
        var checks = UserDefaults.standard.dictionary(forKey: "nsm_motion_checked") as? [String: Double] ?? [:]
        checks[key] = Date().timeIntervalSince1970
        UserDefaults.standard.set(checks, forKey: "nsm_motion_checked")
    }

    private func coverChecked(_ key: String) -> Bool {
        let checks = UserDefaults.standard.dictionary(forKey: "nsm_cover_checked") as? [String: Double] ?? [:]
        guard let stamp = checks[key] else { return false }
        return Date().timeIntervalSince1970 - stamp < 7 * 86_400
    }

    private func markCoverChecked(_ key: String) {
        var checks = UserDefaults.standard.dictionary(forKey: "nsm_cover_checked") as? [String: Double] ?? [:]
        checks[key] = Date().timeIntervalSince1970
        UserDefaults.standard.set(checks, forKey: "nsm_cover_checked")
    }

    private func siteChecked(_ key: String) -> Bool {
        let checks = UserDefaults.standard.dictionary(forKey: "nsm_site_motion_checked_v2") as? [String: Double] ?? [:]
        guard let stamp = checks[key] else { return false }
        return Date().timeIntervalSince1970 - stamp < 6 * 3_600
    }

    private func markSiteChecked(_ key: String) {
        var checks = UserDefaults.standard.dictionary(forKey: "nsm_site_motion_checked_v2") as? [String: Double] ?? [:]
        checks[key] = Date().timeIntervalSince1970
        UserDefaults.standard.set(checks, forKey: "nsm_site_motion_checked_v2")
    }

    static func looseAlbum(_ text: String) -> String {
        var value = text.lowercased()
        for pattern in ["\\([^)]*\\)", "\\[[^\\]]*\\]"] {
            value = value.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        value = value.replacingOccurrences(of: "remastered", with: " ")
        let kept = value.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    private func siteMotion(for track: TrackRecord, key: String) async -> Bool {
        guard let album = track.album, !album.isEmpty else { return false }
        let wanted = Self.looseAlbum(album)
        let artist = track.albumArtist ?? track.artist
        guard !wanted.isEmpty,
              let found = try? await SiteAPI.shared.catalog(search: album, sort: "new", format: nil, limit: 60, offset: 0) else { return false }
        let match = found.first { item in
            guard item.motionFilename != nil, let siteAlbum = item.album else { return false }
            return Self.looseAlbum(siteAlbum) == wanted && TextMatching.artistRatio(artist, item.artist) >= 0.8
        }
        guard let match, let file = match.motionFilename else { return false }
        let local = "site-" + file
        let target = AppPaths.motionURL(local)
        if !FileManager.default.fileExists(atPath: target.path) {
            guard (try? await Net.download(SiteAPI.shared.motionURL(file), to: target)) != nil else { return false }
        }
        var coverName: String?
        if let cover = match.coverFilename {
            let name = "site-" + cover
            let coverTarget = AppPaths.coverURL(name)
            if FileManager.default.fileExists(atPath: coverTarget.path) {
                coverName = name
            } else if (try? await Net.download(SiteAPI.shared.coverURL(cover), to: coverTarget)) != nil {
                coverName = name
            }
        }
        let siblings = ((try? database.allTracks()) ?? []).filter { $0.streamURL == nil && Self.looseAlbumKey($0) == Self.looseAlbumKey(track) }
        for var sibling in siblings {
            sibling.motionName = local
            if sibling.coverName == nil {
                sibling.coverName = coverName
            }
            try? database.save(sibling)
        }
        return true
    }

    private static func looseAlbumKey(_ track: TrackRecord) -> String {
        TextMatching.artistKey(track.albumArtist ?? track.artist) + "|" + looseAlbum(track.album ?? "")
    }

    @discardableResult
    private func findMotion(for track: TrackRecord, force: Bool) async -> Bool {
        guard Self.motionEnabled, let key = Self.albumKey(track), let album = track.album else { return false }
        if track.motionName != nil || albumsDone.contains(key) {
            return false
        }
        albumsDone.insert(key)
        if force || !siteChecked(key) {
            let hit = await siteMotion(for: track, key: key)
            markSiteChecked(key)
            if hit {
                return true
            }
        }
        if !force && checkedRecently(key, days: 30) {
            return false
        }
        let artist = track.albumArtist ?? track.artist
        let files = await MotionCoverFinder.find(
            artist: artist,
            album: album,
            into: AppPaths.motionDir,
            key: Self.fileKey(key)
        )
        markChecked(key)
        guard let files else { return false }
        let siblings = ((try? database.allTracks()) ?? []).filter { Self.albumKey($0) == key }
        for var sibling in siblings {
            sibling.motionName = files.square?.lastPathComponent
            sibling.motion3x4Name = files.tall?.lastPathComponent
            try? database.save(sibling)
        }
        return true
    }

    func enrichLibrary(force: Bool) async {
        guard !libraryRunning else { return }
        libraryRunning = true
        libraryDone = 0
        libraryFound = 0
        defer { libraryRunning = false }

        let everything = ((try? database.allTracks()) ?? []).filter { $0.streamURL == nil }
        var groups: [String: [TrackRecord]] = [:]
        for track in everything where track.coverName == nil {
            let key = Self.albumKey(track) ?? (TextMatching.artistKey(track.artist) + "|" + TextMatching.normalize(track.title))
            groups[key, default: []].append(track)
        }
        let coverJobs = groups.filter { force || !coverChecked($0.key) }
        var albums: [String: TrackRecord] = [:]
        if Self.motionEnabled {
            for track in everything where track.motionName == nil {
                if let key = Self.albumKey(track), albums[key] == nil, force || !siteChecked(key) || !checkedRecently(key, days: 30) {
                    albums[key] = track
                }
            }
        }
        libraryTotal = coverJobs.count + albums.count
        albumsDone.removeAll()

        for (key, tracks) in coverJobs {
            if await fetchCover(for: tracks) {
                libraryFound += 1
            }
            markCoverChecked(key)
            libraryDone += 1
        }
        for (_, track) in albums {
            if await findMotion(for: track, force: force) {
                libraryFound += 1
            }
            libraryDone += 1
        }
    }

    private func fetchCover(for tracks: [TrackRecord]) async -> Bool {
        guard let first = tracks.first else { return false }
        let query = CatalogQuery(
            title: first.title,
            artist: first.artist,
            album: first.album,
            duration: first.durationMs > 0 ? first.durationSeconds : nil
        )
        guard let match = await CatalogClient.lookup(query), let url = match.coverURL,
              let data = try? await Net.data(url),
              let jpeg = ImportManager.normalizedJPEG(data) else { return false }
        let name = "\(UUID().uuidString).jpg"
        do {
            try jpeg.write(to: AppPaths.coverURL(name))
        } catch {
            return false
        }
        for var track in tracks {
            track.coverName = name
            if track.album == nil {
                track.album = match.album
            }
            try? database.save(track)
        }
        return true
    }
}
