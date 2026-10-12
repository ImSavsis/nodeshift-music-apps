import CryptoKit
import Foundation
import NSMCore

@MainActor
final class EnrichmentService {
    private let database: AppDatabase
    private let lyrics: LyricsStore
    private var queue: [TrackRecord] = []
    private var running = false
    private var albumsDone: Set<String> = []

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
            await findMotion(for: track)
        }
        running = false
    }

    private func checkedRecently(_ key: String) -> Bool {
        let checks = UserDefaults.standard.dictionary(forKey: "nsm_motion_checked") as? [String: Double] ?? [:]
        guard let stamp = checks[key] else { return false }
        return Date().timeIntervalSince1970 - stamp < 30 * 86_400
    }

    private func markChecked(_ key: String) {
        var checks = UserDefaults.standard.dictionary(forKey: "nsm_motion_checked") as? [String: Double] ?? [:]
        checks[key] = Date().timeIntervalSince1970
        UserDefaults.standard.set(checks, forKey: "nsm_motion_checked")
    }

    private func findMotion(for track: TrackRecord) async {
        guard Self.motionEnabled, let key = Self.albumKey(track), let album = track.album else { return }
        if albumsDone.contains(key) || checkedRecently(key) || track.motionName != nil {
            return
        }
        albumsDone.insert(key)
        let artist = track.albumArtist ?? track.artist
        let files = await MotionCoverFinder.find(
            artist: artist,
            album: album,
            into: AppPaths.motionDir,
            key: Self.fileKey(key)
        )
        markChecked(key)
        guard let files else { return }
        let siblings = ((try? database.allTracks()) ?? []).filter { Self.albumKey($0) == key }
        for var sibling in siblings {
            sibling.motionName = files.square?.lastPathComponent
            sibling.motion3x4Name = files.tall?.lastPathComponent
            try? database.save(sibling)
        }
    }
}
