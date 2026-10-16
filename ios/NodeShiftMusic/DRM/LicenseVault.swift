import Foundation
import NSMCore

actor LicenseVault {
    static let shared = LicenseVault()

    private var memory: [String: LockedGrant] = [:]
    private var headers: [String: LockedHeader] = [:]
    private let spare: UInt64 = 300
    private let offlineSpare: UInt64 = 7 * 24 * 3600

    private func slot(_ trackID: UInt32, _ kind: LockedKind) -> String {
        "drm_\(trackID)_\(kind.rawValue)"
    }

    private func now() -> UInt64 {
        UInt64(Date().timeIntervalSince1970)
    }

    private func stored(_ trackID: UInt32, _ kind: LockedKind) -> LockedGrant? {
        let key = slot(trackID, kind)
        if let found = memory[key] {
            return found
        }
        guard let text = Keychain.get(key),
              let found = try? JSONDecoder().decode(LockedGrant.self, from: Data(text.utf8)) else { return nil }
        memory[key] = found
        return found
    }

    func lookup(trackID: UInt32, kind: LockedKind, offline: Bool) -> LockedGrant? {
        guard let found = stored(trackID, kind) else { return nil }
        return found.expiresAt > now() + (offline ? offlineSpare : spare) ? found : nil
    }

    func playable(trackID: UInt32, kind: LockedKind) -> LockedGrant? {
        guard let found = stored(trackID, kind) else { return nil }
        return found.expiresAt > now() ? found : nil
    }

    func remember(_ grant: LockedGrant) {
        guard let kind = LockedKind(rawValue: grant.kind) else { return }
        let key = slot(grant.trackID, kind)
        memory[key] = grant
        if let data = try? JSONEncoder().encode(grant), let text = String(data: data, encoding: .utf8) {
            Keychain.set(text, for: key)
        }
    }

    func forget(trackID: UInt32) {
        for kind in [LockedKind.lossless, LockedKind.lossy] {
            let key = slot(trackID, kind)
            memory[key] = nil
            Keychain.remove(key)
        }
    }

    func header(for name: String) -> LockedHeader? {
        headers[name]
    }

    func keepHeader(_ header: LockedHeader, for name: String) {
        headers[name] = header
    }

    func grant(siteID: String, kind: LockedKind, offline: Bool) async throws -> LockedGrant {
        guard let trackID = UInt32(siteID) else {
            throw LockedError.key
        }
        if let found = lookup(trackID: trackID, kind: kind, offline: offline) {
            return found
        }
        let exchange = LicenseExchange()
        let wire = try await SiteAPI.shared.licenses(exchange: exchange, items: [(trackID, kind)], offline: offline)
        let granted = try exchange.open(wire)
        for item in granted {
            remember(item)
        }
        guard let match = granted.first(where: { $0.kind == kind.rawValue }) else {
            throw LockedError.key
        }
        return match
    }

    func grantForPlayback(siteID: String, kind: LockedKind) async throws -> LockedGrant {
        if let trackID = UInt32(siteID), let found = playable(trackID: trackID, kind: kind) {
            return found
        }
        return try await grant(siteID: siteID, kind: kind, offline: false)
    }
}
