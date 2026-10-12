import Foundation
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
            throw SiteError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else { throw SiteError.server(http.statusCode) }
        let token = try decoder().decode(SiteAccessToken.self, from: data).accessToken
        setTokens(access: token, refresh: nil)
        return token
    }

    private func authorizedData(_ path: String) async throws -> Data {
        var token = tokens().access
        if token == nil {
            token = try await refreshAccess()
        }
        for attempt in 0..<2 {
            var request = Net.request(url(path))
            request.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
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

    func coverURL(_ name: String) -> URL {
        mediaBase.appendingPathComponent("covers").appendingPathComponent(name)
    }

    func motionURL(_ name: String) -> URL {
        mediaBase.appendingPathComponent("motion").appendingPathComponent(name)
    }
}
