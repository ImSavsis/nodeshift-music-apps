import Foundation
import Observation
import UIKit

@MainActor
final class PresenceReporter {
    private enum Outcome {
        case done
        case retry
    }

    private weak var player: PlayerStore?
    private weak var site: SiteSession?
    private let sink: any PresenceSink
    private let covers: PresenceCovers
    private let deviceID: String
    private let enabled: @MainActor () -> Bool
    private let backoff: Backoff
    private let startHold: TimeInterval
    private let grace = BackgroundGrace()
    private var heartbeat: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var resyncTask: Task<Void, Never>?
    private var holdTask: Task<Void, Never>?
    private var holdMark: (key: String, since: Date)?
    private var resyncKey = ""
    private var seekMark = -1
    private var dirty = false
    private var forced = false
    private var failures = 0
    private var published = false
    private var gate = PresenceGate()
    private var observers: [NSObjectProtocol] = []

    init(
        sink: any PresenceSink,
        covers: PresenceCovers,
        deviceID: String,
        isEnabled: @escaping @MainActor () -> Bool,
        backoff: Backoff = .standard,
        startHold: TimeInterval = PresenceTiming.startHold
    ) {
        self.sink = sink
        self.covers = covers
        self.deviceID = deviceID
        self.enabled = isEnabled
        self.backoff = backoff
        self.startHold = startHold
    }

    convenience init() {
        let device = BumpSession.deviceID
        self.init(
            sink: SwitchingPresenceSink(hub: HubPresenceSink(device: device), social: SocialPresenceSink()),
            covers: PresenceCovers(),
            deviceID: device,
            isEnabled: { SoundSettings.shared.discordPresence && (SiteAPI.shared.hasSession || DiscordLink.shared.isLinked) }
        )
    }

    private var isEnabled: Bool {
        enabled()
    }

    func attach(player: PlayerStore, site: SiteSession) {
        self.player = player
        self.site = site
        covers.onReady = { [weak self] in
            self?.reconcile()
        }
        observe()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconcile(force: true)
            }
        })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopNow()
            }
        })
        reconcile()
    }

    func stopNow() {
        stopHeartbeat()
        retryTask?.cancel()
        retryTask = nil
        resyncTask?.cancel()
        resyncTask = nil
        resyncKey = ""
        holdTask?.cancel()
        holdTask = nil
        holdMark = nil
        dirty = false
        forced = false
        failures = 0
        gate.reset()
        let hadState = published || worker != nil
        published = false
        if hadState {
            sink.clearDetached()
        }
        settle()
    }

    private func observe() {
        guard let player else { return }
        withObservationTracking {
            _ = player.current?.id
            _ = player.isPlaying
            _ = player.seekToken
            _ = site?.isLoggedIn
            _ = SoundSettings.shared.discordPresence
            _ = DiscordLink.shared.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reconcile()
                self?.observe()
            }
        }
    }

    func reconcile(force: Bool = false) {
        guard let player else { return }
        let live = isEnabled && player.current != nil
        if live && player.isPlaying {
            startHeartbeat()
        } else {
            stopHeartbeat()
        }
        let jumped = player.seekToken != seekMark
        seekMark = player.seekToken
        guard live || published else { return }
        schedule(force: jumped || force)
    }

    private func schedule(force: Bool) {
        retryTask?.cancel()
        retryTask = nil
        dirty = true
        forced = forced || force
        grace.begin("nsm-presence")
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while dirty {
            dirty = false
            let force = forced
            forced = false
            switch await deliver(force: force) {
            case .done:
                failures = 0
                retryTask?.cancel()
                retryTask = nil
            case .retry:
                failures += 1
                if !dirty {
                    scheduleRetry()
                }
            }
        }
        worker = nil
        settle()
    }

    private func settle() {
        guard worker == nil, retryTask == nil, holdTask == nil else { return }
        grace.end()
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = backoff.delay(afterFailures: failures)
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            self?.retryFired()
        }
    }

    private func retryFired() {
        retryTask = nil
        schedule(force: false)
    }

    private func deliver(force: Bool) async -> Outcome {
        guard let player else { return .done }
        guard isEnabled, let snapshot = makeSnapshot(from: player) else {
            return await withdraw()
        }
        let now = Date()
        let key = resyncIdentity(of: player)
        if holding(player, key: key, at: now) {
            forced = forced || force
            armHoldCheck(key)
            return .done
        }
        guard gate.shouldSend(snapshot, at: now, force: force) else { return .done }
        switch await sink.publish(snapshot) {
        case .sent:
            published = true
            gate.recordSent(snapshot, at: now)
            if snapshot.playing {
                armResync(key)
            }
            return .done
        case .rejected:
            return .done
        case .failed:
            gate.reset()
            return .retry
        }
    }

    private func makeSnapshot(from player: PlayerStore) -> PresenceSnapshot? {
        guard let track = player.current else { return nil }
        return PresenceSnapshot.make(
            track: track,
            device: deviceID,
            playing: player.isPlaying,
            position: player.time(at: Date()),
            duration: player.duration,
            cover: covers.url(for: track)
        )
    }

    private func withdraw() async -> Outcome {
        guard published else { return .done }
        switch await sink.clear() {
        case .sent, .rejected:
            published = false
            gate.reset()
            resyncTask?.cancel()
            resyncTask = nil
            resyncKey = ""
            return .done
        case .failed:
            return .retry
        }
    }

    private func holding(_ player: PlayerStore, key: String, at now: Date) -> Bool {
        guard startHold > 0, player.isPlaying, player.position <= 0, player.engineTime <= 0 else {
            holdMark = nil
            return false
        }
        if holdMark?.key != key {
            holdMark = (key: key, since: now)
        }
        guard let since = holdMark?.since else { return false }
        return now.timeIntervalSince(since) < startHold
    }

    private func armHoldCheck(_ key: String) {
        holdTask?.cancel()
        holdTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(PresenceTiming.startPoll))
            } catch {
                return
            }
            self?.holdFired(key)
        }
    }

    private func holdFired(_ key: String) {
        holdTask = nil
        guard let player, resyncIdentity(of: player) == key else {
            settle()
            return
        }
        schedule(force: false)
    }

    private func resyncIdentity(of player: PlayerStore) -> String {
        "\(player.current?.id ?? "")#\(player.seekToken)"
    }

    private func armResync(_ key: String) {
        guard key != resyncKey else { return }
        resyncKey = key
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(PresenceTiming.resync))
            } catch {
                return
            }
            self?.resyncFired(key)
        }
    }

    private func resyncFired(_ key: String) {
        resyncTask = nil
        guard let player, player.isPlaying, resyncIdentity(of: player) == key else { return }
        schedule(force: true)
    }

    private func startHeartbeat() {
        guard heartbeat == nil else { return }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(PresenceTiming.heartbeat))
                } catch {
                    return
                }
                guard let self else { return }
                self.beat()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    private func beat() {
        guard retryTask == nil, worker == nil else { return }
        schedule(force: true)
    }
}
