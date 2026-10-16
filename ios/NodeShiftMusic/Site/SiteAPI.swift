import Foundation
import NSMCore
import Security

enum Keychain {
    private static let service = "space.nodeshift.music"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct FlexibleID: Decodable, Hashable, Sendable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else if let number = try? container.decode(Int.self) {
            value = String(number)
        } else {
            throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "id"))
        }
    }
}

struct SiteUser: Decodable, Equatable, Sendable {
    let id: FlexibleID
    let email: String?
    let username: String?
    let handle: String?
    let avatarUrl: String?

    static func == (lhs: SiteUser, rhs: SiteUser) -> Bool {
        lhs.id == rhs.id
    }
}

struct SiteTokenPair: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let user: SiteUser
}

struct SiteAccessToken: Decodable, Sendable {
    let accessToken: String
}

struct SiteLoginURL: Decodable, Sendable {
    let url: String
}

struct SiteTrack: Decodable, Identifiable, Hashable, Sendable {
    let id: FlexibleID
    let title: String
    let artist: String
    let album: String?
    let durationSeconds: Double?
    let filename: String
    let coverFilename: String?
    let motionFilename: String?
    let streamFilename: String?
    let format: String?
    let playCount: Int?
    let mediaKind: String?

    static func == (lhs: SiteTrack, rhs: SiteTrack) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct SitePlaylist: Decodable, Identifiable, Hashable, Sendable {
    let id: FlexibleID
    let name: String
    let coverFilename: String?
    let trackCount: Int?
    let previewCover: String?
    let previewMotion: String?
}

struct SitePlaylistDetail: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let position: Int
        let track: SiteTrack
    }

    let id: FlexibleID
    let name: String
    let coverFilename: String?
    let tracks: [Entry]
}

struct SiteLibraryState: Decodable, Sendable {
    let favoriteIds: [FlexibleID]
    let wishlistIds: [FlexibleID]?
}

struct SiteLibrary: Sendable {
    let favorites: Set<String>
    let wishlist: Set<String>
}

struct SiteRoomInfo: Decodable, Sendable {
    struct Playing: Decodable, Sendable {
        let title: String
        let artist: String
    }

    let code: String
    let members: Int
    let playing: Bool
    let track: Playing?
}

struct SiteRoomCreated: Decodable, Sendable {
    let code: String
}

struct SiteLyrics: Decodable, Sendable {
    let synced: String?
    let plain: String?
    let source: String?
}

enum SiteError: Error {
    case cancelled
    case noToken
    case badCallback
    case unauthorized
    case server(Int)
}

extension Notification.Name {
    static let nsmSessionExpired = Notification.Name("space.nodeshift.music.session-expired")
}

struct PresencePayload: Encodable, Equatable, Sendable {
    var stop: Bool?
    var device: String
    var platform: String?
    var playing: Bool?
    var title: String?
    var artist: String?
    var album: String?
    var positionMs: Int?
    var durationMs: Int?
    var cover: String?
    var siteId: String?

    enum CodingKeys: String, CodingKey {
        case stop, device, platform, playing, title, artist, album, cover
        case positionMs = "position_ms"
        case durationMs = "duration_ms"
        case siteId = "site_id"
    }

    init(_ snapshot: PresenceSnapshot) {
        device = snapshot.device
        platform = snapshot.platform
        playing = snapshot.playing
        title = snapshot.title
        artist = snapshot.artist
        album = snapshot.album
        positionMs = snapshot.positionMs
        durationMs = snapshot.durationMs
        cover = snapshot.cover
        siteId = snapshot.siteId
    }

    private init(stoppingDevice device: String) {
        stop = true
        self.device = device
    }

    static func stopping(device: String) -> PresencePayload {
        PresencePayload(stoppingDevice: device)
    }

    func advanced(by milliseconds: Int) -> PresencePayload {
        guard milliseconds > 0, playing == true, let position = positionMs else { return self }
        var moved = self
        let target = position + milliseconds
        if let total = durationMs, total > 0 {
            moved.positionMs = min(target, total)
        } else {
            moved.positionMs = target
        }
        return moved
    }
}

final class SiteAPI: @unchecked Sendable {
    static let shared = SiteAPI()

    let base = URL(string: "https://music.nodeshift.space")!
    let mediaBase = URL(string: "https://burmalda.savsis.xyz")!

    private let lock = NSLock()
    private var access: String?
    private var refresh: String?

    init() {
        access = Keychain.get("access")
        refresh = Keychain.get("refresh")
    }

    var hasSession: Bool {
        lock.lock()
        defer { lock.unlock() }
        return refresh != nil
    }

    func setTokens(access: String?, refresh: String?) {
        lock.lock()
        self.access = access
        if let refresh {
            self.refresh = refresh
        }
        lock.unlock()
        if let access {
            Keychain.set(access, for: "access")
        }
        if let refresh {
            Keychain.set(refresh, for: "refresh")
        }
    }

    func clear() {
        lock.lock()
        access = nil
        refresh = nil
        lock.unlock()
        Keychain.remove("access")
        Keychain.remove("refresh")
    }

    private func tokens() -> (access: String?, refresh: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (access, refresh)
    }

    private func url(_ path: String) -> URL {
        URL(string: path, relativeTo: base)!.absoluteURL
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    func loginURL() async throws -> URL {
        let data = try await Net.data(url("/api/auth/login-url?client=native"))
        let payload = try decoder().decode(SiteLoginURL.self, from: data)
        guard let link = URL(string: payload.url) else { throw SiteError.badCallback }
        return link
    }

    func ssoLogin(token: String, state: String) async throws -> SiteTokenPair {
        var request = Net.request(url("/api/auth/sso-login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["sso_token": token, "state": state])
        let (data, response) = try await Net.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SiteError.server((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try decoder().decode(SiteTokenPair.self, from: data)
    }

    @discardableResult
    func refreshAccess() async throws -> String {
        guard let refreshToken = tokens().refresh else { throw SiteError.noToken }
        var request = Net.request(url("/api/auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let (data, response) = try await Net.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SiteError.server(0) }
        if http.statusCode == 401 || http.statusCode == 400 {
            clear()
            NotificationCenter.default.post(name: .nsmSessionExpired, object: nil)
            throw SiteError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else { throw SiteError.server(http.statusCode) }
        let token = try decoder().decode(SiteAccessToken.self, from: data).accessToken
        setTokens(access: token, refresh: nil)
        return token
    }

    func freshAccessToken() async -> String? {
        guard hasSession else { return nil }
        if let refreshed = try? await refreshAccess() {
            return refreshed
        }
        return tokens().access
    }

    private func authorizedData(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        var token = tokens().access
        if token == nil {
            token = try await refreshAccess()
        }
        for attempt in 0..<2 {
            var request = Net.request(url(path))
            request.httpMethod = method
            request.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            let (data, response) = try await Net.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SiteError.server(0) }
            if http.statusCode == 401, attempt == 0 {
                token = try await refreshAccess()
                continue
            }
            guard (200..<300).contains(http.statusCode) else {
                throw http.statusCode == 401 ? SiteError.unauthorized : SiteError.server(http.statusCode)
            }
            return data
        }
        throw SiteError.unauthorized
    }

    func me() async throws -> SiteUser {
        try decoder().decode(SiteUser.self, from: try await authorizedData("/api/auth/me"))
    }

    func favorites() async throws -> [SiteTrack] {
        try decoder().decode([SiteTrack].self, from: try await authorizedData("/api/music/favorites"))
    }

    func playlists() async throws -> [SitePlaylist] {
        try decoder().decode([SitePlaylist].self, from: try await authorizedData("/api/music/playlists"))
    }

    func playlist(_ id: String) async throws -> SitePlaylistDetail {
        try decoder().decode(SitePlaylistDetail.self, from: try await authorizedData("/api/music/playlists/\(id)"))
    }

    func catalog(search: String, sort: String, format: String?, limit: Int, offset: Int) async throws -> [SiteTrack] {
        var items = ["sort": sort, "limit": String(limit), "offset": String(offset)]
        if !search.isEmpty {
            items["search"] = search
        }
        if let format {
            items["format"] = format
        }
        guard let link = Net.components(url("/api/music/tracks").absoluteString, items) else {
            throw SiteError.badCallback
        }
        return try decoder().decode([SiteTrack].self, from: try await Net.data(link))
    }

    func wave(limit: Int) async throws -> [SiteTrack] {
        guard let link = Net.components(url("/api/music/wave").absoluteString, ["limit": String(limit)]) else {
            throw SiteError.badCallback
        }
        return try decoder().decode([SiteTrack].self, from: try await Net.data(link))
    }

    func registerPlay(_ trackID: String) async {
        var request = Net.request(url("/api/music/tracks/\(trackID)/play"))
        request.httpMethod = "POST"
        _ = try? await Net.session.data(for: request)
    }

    func libraryState() async throws -> SiteLibrary {
        let state = try decoder().decode(SiteLibraryState.self, from: try await authorizedData("/api/music/me/library"))
        return SiteLibrary(
            favorites: Set(state.favoriteIds.map { $0.value }),
            wishlist: Set((state.wishlistIds ?? []).map { $0.value })
        )
    }

    func likedIDs() async throws -> Set<String> {
        try await libraryState().favorites
    }

    func setLiked(_ trackID: String, value: Bool) async throws {
        _ = try await authorizedData("/api/music/favorites/\(trackID)", method: value ? "POST" : "DELETE")
    }

    func wishlist() async throws -> [SiteTrack] {
        try decoder().decode([SiteTrack].self, from: try await authorizedData("/api/music/wishlist"))
    }

    func setWishlisted(_ trackID: String, value: Bool) async throws {
        _ = try await authorizedData("/api/music/wishlist/\(trackID)", method: value ? "POST" : "DELETE")
    }

    func createPlaylist(name: String) async throws -> SitePlaylist {
        let data = try await authorizedData("/api/music/playlists", method: "POST", body: ["name": name])
        return try decoder().decode(SitePlaylist.self, from: data)
    }

    func renamePlaylist(_ id: String, name: String) async throws {
        _ = try await authorizedData("/api/music/playlists/\(id)", method: "PATCH", body: ["name": name])
    }

    func deletePlaylist(_ id: String) async throws {
        _ = try await authorizedData("/api/music/playlists/\(id)", method: "DELETE")
    }

    func addToPlaylist(_ id: String, trackID: String) async throws {
        guard let numeric = Int(trackID) else { throw SiteError.badCallback }
        _ = try await authorizedData("/api/music/playlists/\(id)/tracks", method: "POST", body: ["track_id": numeric])
    }

    func removeFromPlaylist(_ id: String, trackID: String) async throws {
        _ = try await authorizedData("/api/music/playlists/\(id)/tracks/\(trackID)", method: "DELETE")
    }

    func createRoom() async throws -> String {
        let data = try await authorizedData("/api/music/rooms", method: "POST")
        return try decoder().decode(SiteRoomCreated.self, from: data).code
    }

    func roomInfo(_ code: String) async throws -> SiteRoomInfo? {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        do {
            let data = try await Net.data(url("/api/music/rooms/\(encoded)"))
            return try decoder().decode(SiteRoomInfo.self, from: data)
        } catch NetError.notFound {
            return nil
        }
    }

    func roomSocketURL(_ code: String) -> URL? {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.scheme = "wss"
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        components?.path = "/api/music/rooms/\(encoded)/ws"
        return components?.url
    }

    func roomLink(_ code: String) -> URL {
        base.appendingPathComponent("room").appendingPathComponent(code)
    }

    func publishPresence(_ payload: PresencePayload) async -> PresenceResult {
        guard hasSession else { return .rejected }
        let started = Date()
        var token = tokens().access
        if token == nil {
            token = try? await refreshAccess()
        }
        for attempt in 0..<2 {
            guard let bearer = token else { return hasSession ? .failed : .rejected }
            let lag = Int(Date().timeIntervalSince(started) * 1000)
            guard let body = try? JSONEncoder().encode(payload.advanced(by: lag)) else { return .rejected }
            var request = Net.request(bumpBase.appendingPathComponent("presence"))
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            request.httpBody = body
            guard let (_, response) = try? await Net.session.data(for: request),
                  let http = response as? HTTPURLResponse else { return .failed }
            if http.statusCode == 401 {
                guard attempt == 0 else { return .failed }
                token = try? await refreshAccess()
                continue
            }
            return PresenceResult.classify(status: http.statusCode)
        }
        return .failed
    }

    func stopPresenceDetached(device: String) {
        let pair = tokens()
        guard pair.access != nil || pair.refresh != nil,
              let body = try? JSONEncoder().encode(PresencePayload.stopping(device: device)) else { return }
        Task.detached {
            await self.sendStop(body, access: pair.access, refresh: pair.refresh)
        }
    }

    private func sendStop(_ body: Data, access: String?, refresh: String?) async {
        var token = access
        if token == nil, let refresh {
            token = await accessToken(refreshedWith: refresh)
        }
        for attempt in 0..<2 {
            guard let bearer = token else { return }
            var request = Net.request(bumpBase.appendingPathComponent("presence"))
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            request.httpBody = body
            guard let (_, response) = try? await Net.session.data(for: request),
                  let http = response as? HTTPURLResponse else { return }
            guard http.statusCode == 401, attempt == 0, let refreshToken = refresh else { return }
            token = await accessToken(refreshedWith: refreshToken)
        }
    }

    private func accessToken(refreshedWith refreshToken: String) async -> String? {
        var request = Net.request(url("/api/auth/refresh"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        guard let (data, response) = try? await Net.session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return (try? decoder().decode(SiteAccessToken.self, from: data))?.accessToken
    }

    func uploadPresenceArt(_ jpeg: Data) async -> String? {
        guard hasSession, jpeg.count <= PresenceCoverRules.maxArtBytes else { return nil }
        var token = tokens().access
        if token == nil {
            token = try? await refreshAccess()
        }
        for attempt in 0..<2 {
            guard let bearer = token else { return nil }
            var request = Net.request(bumpBase.appendingPathComponent("presence").appendingPathComponent("art"))
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            request.httpBody = jpeg
            guard let (data, response) = try? await Net.session.data(for: request),
                  let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 401, attempt == 0 {
                token = try? await refreshAccess()
                continue
            }
            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return PresenceCoverRules.https(json["url"] as? String)
        }
        return nil
    }

    var bumpBase: URL {
        base.appendingPathComponent("app").appendingPathComponent("bump")
    }

    func lyrics(_ trackID: String) async -> SiteLyrics? {
        guard let data = try? await Net.data(url("/api/music/lyrics/\(trackID)")) else { return nil }
        return try? decoder().decode(SiteLyrics.self, from: data)
    }

    func audioURL(_ track: SiteTrack, lossless: Bool) -> URL {
        if !lossless, let stream = track.streamFilename {
            return mediaBase.appendingPathComponent("stream").appendingPathComponent(stream)
        }
        return mediaBase.appendingPathComponent("tracks").appendingPathComponent(track.filename)
    }

    func previewURL(_ trackID: String) -> URL {
        base.appendingPathComponent("api").appendingPathComponent("music").appendingPathComponent("preview").appendingPathComponent(trackID)
    }

    func lockedURL(_ name: String) -> URL {
        mediaBase.appendingPathComponent("locked").appendingPathComponent(name)
    }

    func licenses(exchange: LicenseExchange, items: [(UInt32, LockedKind)], offline: Bool) async throws -> LicenseWire {
        let wanted: [[String: Any]] = items.map { ["track_id": Int($0.0), "kind": $0.1.name] }
        let body: [String: Any] = ["client_pub": exchange.publicBase64, "items": wanted, "offline": offline]
        let data = try await authorizedData("/api/music/license", method: "POST", body: body)
        return try JSONDecoder().decode(LicenseWire.self, from: data)
    }

    func coverURL(_ name: String) -> URL {
        mediaBase.appendingPathComponent("covers").appendingPathComponent(name)
    }

    func thumbURL(_ name: String) -> URL {
        let stem = (name as NSString).deletingPathExtension
        return mediaBase.appendingPathComponent("thumbs").appendingPathComponent("\(stem).webp")
    }

    func motionURL(_ name: String) -> URL {
        mediaBase.appendingPathComponent("motion").appendingPathComponent(name)
    }
}
