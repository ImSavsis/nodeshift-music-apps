import Foundation
import Observation

@MainActor
@Observable
final class DiscordLink {
    static let shared = DiscordLink()
    static let applicationID: UInt64 = 1498024819675889704
    static let displayName = "Burmalda"

    enum State: Equatable {
        case unavailable
        case unlinked
        case linking
        case linked
        case failed(String)
    }

    private struct Tokens {
        var access: String?
        var refresh: String?
        var expiresIn: Int
        var error: String?
    }

    private(set) var state: State
    private(set) var isReady = false

    @ObservationIgnored private let bridge = NSMDiscordBridge.shared
    @ObservationIgnored private var expiresAt: Date?
    @ObservationIgnored private var connectedToken: String?
    @ObservationIgnored private var preparing: Task<Bool, Never>?

    var isLinked: Bool {
        state == .linked
    }

    private init() {
        if !NSMDiscordBridge.shared.available {
            state = .unavailable
        } else if Keychain.get("discord_refresh") != nil {
            state = .linked
        } else {
            state = .unlinked
        }
        let stamp = UserDefaults.standard.double(forKey: "nsm_discord_expires")
        expiresAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    func restore() {
        guard state == .linked else { return }
        configure()
        Task {
            _ = await prepare()
        }
    }

    func link() async {
        guard bridge.available, state != .linking else { return }
        state = .linking
        configure()
        let tokens = await authorize()
        guard let access = tokens.access, let refresh = tokens.refresh else {
            state = .failed(Self.explain(tokens.error))
            return
        }
        store(access: access, refresh: refresh, expiresIn: tokens.expiresIn)
        state = .linked
        _ = await connect(access)
    }

    func unlink() {
        bridge.clearPresence()
        bridge.disconnect()
        Keychain.remove("discord_access")
        Keychain.remove("discord_refresh")
        UserDefaults.standard.removeObject(forKey: "nsm_discord_expires")
        expiresAt = nil
        connectedToken = nil
        isReady = false
        state = bridge.available ? .unlinked : .unavailable
    }

    func prepare() async -> Bool {
        if let preparing {
            return await preparing.value
        }
        let task = Task { await self.makeReady() }
        preparing = task
        let ready = await task.value
        preparing = nil
        return ready
    }

    private func configure() {
        bridge.configure(Self.applicationID)
        bridge.onStatusChange = { [weak self] ready in
            Task { @MainActor in
                self?.isReady = ready
            }
        }
    }

    private var needsRefresh: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 3600
    }

    private func makeReady() async -> Bool {
        guard state == .linked else { return false }
        configure()
        var access = Keychain.get("discord_access")
        if access == nil || needsRefresh {
            guard let refresh = Keychain.get("discord_refresh") else { return false }
            let tokens = await refreshTokens(refresh)
            guard let newAccess = tokens.access, let newRefresh = tokens.refresh else { return false }
            store(access: newAccess, refresh: newRefresh, expiresIn: tokens.expiresIn)
            access = newAccess
        }
        guard let access else { return false }
        if connectedToken != access {
            guard await connect(access) else { return false }
        }
        return await waitUntilReady()
    }

    private func waitUntilReady() async -> Bool {
        for _ in 0..<40 {
            if isReady { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return isReady
    }

    private func store(access: String, refresh: String, expiresIn: Int) {
        Keychain.set(access, for: "discord_access")
        Keychain.set(refresh, for: "discord_refresh")
        let seconds = expiresIn > 0 ? expiresIn : 604_800
        let expires = Date().addingTimeInterval(TimeInterval(seconds))
        expiresAt = expires
        UserDefaults.standard.set(expires.timeIntervalSince1970, forKey: "nsm_discord_expires")
    }

    private func authorize() async -> Tokens {
        await withCheckedContinuation { continuation in
            bridge.authorize { access, refresh, expiresIn, error in
                continuation.resume(returning: Tokens(access: access, refresh: refresh, expiresIn: expiresIn, error: error))
            }
        }
    }

    private func refreshTokens(_ refresh: String) async -> Tokens {
        await withCheckedContinuation { continuation in
            bridge.refresh(refresh) { access, newRefresh, expiresIn, error in
                continuation.resume(returning: Tokens(access: access, refresh: newRefresh, expiresIn: expiresIn, error: error))
            }
        }
    }

    private func connect(_ access: String) async -> Bool {
        let ok: Bool = await withCheckedContinuation { continuation in
            bridge.connect(access) { ok, _, _ in
                continuation.resume(returning: ok)
            }
        }
        if ok {
            connectedToken = access
        }
        return ok
    }

    private static func explain(_ error: String?) -> String {
        guard let error, !error.isEmpty else { return "Не получилось привязать Discord. Попробуй ещё раз." }
        return "Discord ответил: \(error)"
    }
}
