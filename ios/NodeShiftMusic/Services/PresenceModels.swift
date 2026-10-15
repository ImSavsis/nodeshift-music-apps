import Foundation

enum PresenceResult: Sendable, Equatable {
    case sent
    case rejected
    case failed

    static func classify(status: Int) -> PresenceResult {
        if (200..<300).contains(status) {
            return .sent
        }
        if status == 408 || status == 425 || status == 429 || status >= 500 {
            return .failed
        }
        return .rejected
    }
}

struct PresenceSnapshot: Equatable, Sendable {
    var device: String
    var platform: String
    var playing: Bool
    var title: String
    var artist: String
    var album: String
    var positionMs: Int
    var durationMs: Int
    var cover: String?
    var siteId: String?

    static func make(
        track: TrackRecord,
        device: String,
        playing: Bool,
        position: Double,
        duration: Double,
        cover: String?
    ) -> PresenceSnapshot? {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let total = milliseconds(duration)
        let at = milliseconds(position)
        return PresenceSnapshot(
            device: device,
            platform: "ios",
            playing: playing,
            title: title,
            artist: track.artist,
            album: track.album ?? "",
            positionMs: total > 0 ? min(at, total) : at,
            durationMs: total,
            cover: cover,
            siteId: track.siteId
        )
    }

    static func milliseconds(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds, 360_000) * 1000)
    }

    func sameContent(as other: PresenceSnapshot) -> Bool {
        var aligned = other
        aligned.positionMs = positionMs
        return aligned == self
    }
}

@MainActor
protocol PresenceSink {
    func publish(_ snapshot: PresenceSnapshot) async -> PresenceResult
    func clear() async -> PresenceResult
    func clearDetached()
}
