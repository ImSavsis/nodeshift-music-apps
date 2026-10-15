import Foundation

@MainActor
struct SocialPresenceSink: PresenceSink {
    func publish(_ snapshot: PresenceSnapshot) async -> PresenceResult {
        let link = DiscordLink.shared
        guard link.isLinked else { return .rejected }
        guard snapshot.playing else { return await clear() }
        guard await link.prepare() else { return .failed }

        let nowMs = Date().timeIntervalSince1970 * 1000
        let start = UInt64(max(0, nowMs - Double(snapshot.positionMs)))
        let end = snapshot.durationMs > 0 ? start + UInt64(snapshot.durationMs) : 0
        var info: [String: Any] = [
            "name": DiscordLink.displayName,
            "title": snapshot.title,
            "artist": snapshot.artist,
            "album": snapshot.album,
            "start": NSNumber(value: start),
            "end": NSNumber(value: end),
        ]
        if let cover = snapshot.cover {
            info["cover"] = cover
        }
        info["page"] = Self.link(for: snapshot)
        return await withCheckedContinuation { continuation in
            NSMDiscordBridge.shared.publish(info) { ok, retryable, _ in
                continuation.resume(returning: ok ? .sent : (retryable ? .failed : .rejected))
            }
        }
    }

    private static func link(for snapshot: PresenceSnapshot) -> String {
        if let siteId = snapshot.siteId?.replacingOccurrences(of: "site:", with: ""), !siteId.isEmpty {
            return "https://music.nodeshift.space/track/\(siteId)"
        }
        let query = String("\(snapshot.artist) \(snapshot.title)".trimmingCharacters(in: .whitespaces).prefix(60))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return "https://music.apple.com/search?term=\(encoded)"
    }

    func clear() async -> PresenceResult {
        NSMDiscordBridge.shared.clearPresence()
        return .sent
    }

    func clearDetached() {
        NSMDiscordBridge.shared.clearPresence()
    }
}

@MainActor
final class SwitchingPresenceSink: PresenceSink {
    private let hub: any PresenceSink
    private let social: any PresenceSink
    private var usedSocial = false

    init(hub: any PresenceSink, social: any PresenceSink) {
        self.hub = hub
        self.social = social
    }

    func publish(_ snapshot: PresenceSnapshot) async -> PresenceResult {
        let linked = DiscordLink.shared.isLinked
        if linked != usedSocial {
            _ = await (usedSocial ? social : hub).clear()
            usedSocial = linked
        }
        return await (linked ? social : hub).publish(snapshot)
    }

    func clear() async -> PresenceResult {
        await (usedSocial ? social : hub).clear()
    }

    func clearDetached() {
        (usedSocial ? social : hub).clearDetached()
    }
}
