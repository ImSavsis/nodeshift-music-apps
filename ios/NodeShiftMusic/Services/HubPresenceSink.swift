import Foundation

@MainActor
struct HubPresenceSink: PresenceSink {
    let device: String

    func publish(_ snapshot: PresenceSnapshot) async -> PresenceResult {
        await SiteAPI.shared.publishPresence(PresencePayload(snapshot))
    }

    func clear() async -> PresenceResult {
        await SiteAPI.shared.publishPresence(PresencePayload.stopping(device: device))
    }

    func clearDetached() {
        SiteAPI.shared.stopPresenceDetached(device: device)
    }
}
