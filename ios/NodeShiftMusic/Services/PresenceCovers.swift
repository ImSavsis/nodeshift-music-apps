import Foundation

enum PresenceArt {
    static func jpeg(at file: URL) -> Data? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        var jpeg = ImportManager.normalizedJPEG(data, maxSide: 600)
        if let current = jpeg, current.count > PresenceCoverRules.reencodeAbove {
            jpeg = ImportManager.normalizedJPEG(data, maxSide: 360)
        }
        guard let result = jpeg, result.count <= PresenceCoverRules.maxArtBytes else { return nil }
        return result
    }
}

@MainActor
final class PresenceCovers {
    typealias Uploader = @Sendable (Data) async -> String?
    typealias Loader = @Sendable (String) -> Data?
    typealias Now = @MainActor () -> Date

    static let storeKey = "nsm_presence_art"
    static let stampKey = "nsm_presence_art_at"

    var onReady: (() -> Void)?

    private let upload: Uploader
    private let load: Loader
    private let defaults: UserDefaults
    private let now: Now
    private var uploaded: [String: String]
    private var stamps: [String: TimeInterval]
    private var blocks = PresenceCoverBlocks()
    private var running: [String: Task<Void, Never>] = [:]

    init(
        upload: @escaping Uploader,
        load: @escaping Loader = { PresenceArt.jpeg(at: AppPaths.coverURL($0)) },
        defaults: UserDefaults = .standard,
        now: @escaping Now = { Date() }
    ) {
        self.upload = upload
        self.load = load
        self.defaults = defaults
        self.now = now
        let saved = defaults.dictionary(forKey: Self.storeKey) as? [String: String] ?? [:]
        let kept = saved.filter { PresenceCoverRules.https($0.value) != nil }
        let savedStamps = defaults.dictionary(forKey: Self.stampKey) as? [String: TimeInterval] ?? [:]
        uploaded = kept
        stamps = savedStamps.filter { kept[$0.key] != nil }
    }

    convenience init() {
        self.init(upload: { await SiteAPI.shared.uploadPresenceArt($0) })
    }

    func url(for track: TrackRecord) -> String? {
        guard let name = track.coverName else { return nil }
        if CoverSource.isRemote(name) {
            return PresenceCoverRules.https(CoverSource.fullURL(for: name).absoluteString)
        }
        if name.hasPrefix("site-") {
            return PresenceCoverRules.https(SiteAPI.shared.coverURL(String(name.dropFirst(5))).absoluteString)
        }
        let moment = now()
        guard let known = uploaded[name] else {
            startUpload(name, at: moment)
            return nil
        }
        switch PresenceCoverRules.freshness(uploadedAt: uploadedAt(name), now: moment) {
        case .fresh:
            return known
        case .stale:
            startUpload(name, at: moment)
            return known
        case .expired:
            startUpload(name, at: moment)
            return nil
        }
    }

    private func uploadedAt(_ name: String) -> Date? {
        stamps[name].map { Date(timeIntervalSince1970: $0) }
    }

    private func startUpload(_ name: String, at moment: Date) {
        guard running[name] == nil, !blocks.isBlocked(name, at: moment) else { return }
        let send = upload
        let read = load
        running[name] = Task { [weak self] in
            let url = await Task.detached(priority: .utility) { () async -> String? in
                guard let jpeg = read(name) else { return nil }
                return await send(jpeg)
            }.value
            self?.finishUpload(name, url: url)
        }
    }

    private func finishUpload(_ name: String, url: String?) {
        running[name] = nil
        let moment = now()
        guard let url = PresenceCoverRules.https(url) else {
            blocks.block(name, from: moment)
            return
        }
        uploaded[name] = url
        stamps[name] = moment.timeIntervalSince1970
        defaults.set(uploaded, forKey: Self.storeKey)
        defaults.set(stamps, forKey: Self.stampKey)
        onReady?()
    }
}
