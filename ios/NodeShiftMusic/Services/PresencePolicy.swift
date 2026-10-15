import Foundation

enum PresenceTiming {
    static let heartbeat: TimeInterval = 15
    static let resync: TimeInterval = 2
    static let startHold: TimeInterval = 3
    static let startPoll: TimeInterval = 0.25
}

struct Backoff: Equatable, Sendable {
    let steps: [TimeInterval]

    static let standard = Backoff(steps: [2, 4, 8, 16, 30])

    var attempts: Int {
        steps.count + 1
    }

    func delay(afterFailures failures: Int) -> TimeInterval {
        guard let last = steps.last else { return 0 }
        let index = max(failures, 1) - 1
        return index < steps.count ? steps[index] : last
    }
}

struct PresenceGate: Sendable {
    static let positionTolerance = 2500

    private struct Entry: Sendable {
        var snapshot: PresenceSnapshot
        var at: Date
    }

    private var last: Entry?

    func shouldSend(_ next: PresenceSnapshot, at now: Date, force: Bool) -> Bool {
        guard !force, let previous = last else { return true }
        guard previous.snapshot.sameContent(as: next) else { return true }
        return abs(next.positionMs - expectedPosition(of: previous, at: now)) > Self.positionTolerance
    }

    mutating func recordSent(_ snapshot: PresenceSnapshot, at now: Date) {
        last = Entry(snapshot: snapshot, at: now)
    }

    mutating func reset() {
        last = nil
    }

    private func expectedPosition(of entry: Entry, at now: Date) -> Int {
        guard entry.snapshot.playing else { return entry.snapshot.positionMs }
        let advanced = entry.snapshot.positionMs + max(0, Int(now.timeIntervalSince(entry.at) * 1000))
        guard entry.snapshot.durationMs > 0 else { return advanced }
        return min(advanced, entry.snapshot.durationMs)
    }
}

struct PresenceCoverBlocks: Sendable, Equatable {
    static let window: TimeInterval = 300

    private var until: [String: Date] = [:]

    func isBlocked(_ name: String, at now: Date) -> Bool {
        guard let limit = until[name] else { return false }
        return limit > now
    }

    mutating func block(_ name: String, from now: Date) {
        until = until.filter { $0.value > now }
        until[name] = now.addingTimeInterval(Self.window)
    }
}

enum PresenceCoverFreshness: Equatable, Sendable {
    case fresh
    case stale
    case expired
}

enum PresenceCoverRules {
    static let maxArtBytes = 600_000
    static let reencodeAbove = 580_000
    static let refreshAfter: TimeInterval = 30 * 86400
    static let expireAfter: TimeInterval = 75 * 86400

    static func https(_ value: String?) -> String? {
        guard let value, value.hasPrefix("https://") else { return nil }
        return value
    }

    static func freshness(uploadedAt: Date?, now: Date) -> PresenceCoverFreshness {
        guard let uploadedAt else { return .stale }
        let age = now.timeIntervalSince(uploadedAt)
        if age >= expireAfter {
            return .expired
        }
        return age >= refreshAfter ? .stale : .fresh
    }
}

struct InterruptionPolicy: Equatable, Sendable {
    enum Event: Equatable, Sendable {
        case began
        case ended(shouldResume: Bool)
    }

    enum Action: Equatable, Sendable {
        case nothing
        case pause
        case resume
    }

    private var resumeAfter = false

    mutating func handle(_ event: Event, isPlaying: Bool) -> Action {
        switch event {
        case .began:
            resumeAfter = isPlaying
            return isPlaying ? .pause : .nothing
        case .ended(let shouldResume):
            let resume = resumeAfter && shouldResume && !isPlaying
            resumeAfter = false
            return resume ? .resume : .nothing
        }
    }
}
