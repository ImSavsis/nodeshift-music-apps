import CryptoKit
import Foundation
import NSMCore

struct CatalogMotionEntry: Codable {
    var square: String?
    var tall: String?
    var checked: Double
}

@MainActor
final class CatalogMotion {
    static let shared = CatalogMotion()

    private let storeKey = "nsm_catalog_motion"
    private var entries: [String: CatalogMotionEntry]
    private var running = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let decoded = try? JSONDecoder().decode([String: CatalogMotionEntry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func entry(for track: TrackRecord) -> CatalogMotionEntry? {
        guard let key = EnrichmentService.albumKey(track), let found = entries[key], found.square != nil || found.tall != nil else {
            return nil
        }
        return found
    }

    func apply(to track: inout TrackRecord) {
        guard track.motionName == nil, let found = entry(for: track) else { return }
        track.motionName = found.square.map { "cache:" + $0 }
        track.motion3x4Name = found.tall.map { "cache:" + $0 }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private static func fileKey(_ albumKey: String) -> String {
        let digest = SHA256.hash(data: Data(albumKey.utf8))
        return "c" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func run(tracks: [TrackRecord], onFound: @escaping () -> Void) {
        guard !running, EnrichmentService.motionEnabled, SoundSettings.shared.motionCovers else { return }
        var albums: [String: TrackRecord] = [:]
        let now = Date().timeIntervalSince1970
        for track in tracks where track.isRemote && track.motionName == nil {
            guard let key = EnrichmentService.albumKey(track), albums[key] == nil else { continue }
            if let known = entries[key], now - known.checked < 30 * 86_400 {
                continue
            }
            albums[key] = track
        }
        guard !albums.isEmpty else { return }
        running = true
        Task { [weak self] in
            for (key, track) in albums {
                guard let self, NetworkMonitor.shared.isUnmetered else { break }
                let artist = track.albumArtist ?? track.artist
                let files = await MotionCoverFinder.find(
                    artist: artist,
                    album: track.album ?? "",
                    into: AppPaths.motionCacheDir,
                    key: Self.fileKey(key)
                )
                self.entries[key] = CatalogMotionEntry(
                    square: files?.square?.lastPathComponent,
                    tall: files?.tall?.lastPathComponent,
                    checked: Date().timeIntervalSince1970
                )
                self.save()
                if files != nil {
                    onFound()
                }
            }
            self?.running = false
        }
    }
}
