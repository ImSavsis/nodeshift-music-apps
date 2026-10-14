import Foundation
import Observation

struct RoomMember: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let userID: Int?
}

struct RoomState: Equatable, Sendable {
    var index: Int
    var trackID: String?
    var playing: Bool
    var position: Double
    var stamp: Double
    var repeatMode: String
    var shuffle: Bool
    var by: String?
}

enum RoomStatus: Equatable, Sendable {
    case idle
    case connecting
    case live
    case reconnecting
}

private struct PlayerSnapshot: Equatable {
    var siteID: String?
    var queueIDs: [String]
    var index: Int?
    var playing: Bool
    var seekToken: Int
    var shuffle: Bool
    var repeatMode: RepeatMode
}

@MainActor
@Observable
final class RoomStore {
    private(set) var code: String?
    private(set) var status: RoomStatus = .idle
    private(set) var members: [RoomMember] = []
    private(set) var you: String?
    private(set) var notice: String?

    @ObservationIgnored private weak var player: PlayerStore?
    @ObservationIgnored private weak var catalog: CatalogStore?
    @ObservationIgnored private weak var toasts: ToastCenter?
    @ObservationIgnored private let api = SiteAPI.shared
    @ObservationIgnored private let session = URLSession(configuration: .default)
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var closedByUser = true
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var pingTimer: Timer?
    @ObservationIgnored private var driftTimer: Timer?
    @ObservationIgnored private var reconnectWork: DispatchWorkItem?
    @ObservationIgnored private var clockOffset = 0.0
    @ObservationIgnored private var bestRTT = Double.infinity
    @ObservationIgnored private var roomQueue: [SiteTrack] = []
    @ObservationIgnored private var lastState: RoomState?
    @ObservationIgnored private var applyToken = 0
    @ObservationIgnored private var stateCount = 0
    @ObservationIgnored private var awaitingFirstState = false
    @ObservationIgnored private var silent = 0
    @ObservationIgnored private var previous: PlayerSnapshot?
    @ObservationIgnored private var guestName = ""

    static let maxRetries = 12
    static let driftTolerance = 0.7
    static let seekTolerance = 0.35

    var isLive: Bool {
        status == .live && socket != nil
    }

    var link: URL? {
        code.map { api.roomLink($0) }
    }

    func attach(player: PlayerStore, catalog: CatalogStore, toasts: ToastCenter) {
        self.player = player
        self.catalog = catalog
        self.toasts = toasts
    }

    static func savedGuestName() -> String {
        UserDefaults.standard.string(forKey: "nsm_guest_name") ?? ""
    }

    static func saveGuestName(_ name: String) {
        UserDefaults.standard.set(name, forKey: "nsm_guest_name")
    }

    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let host = url.host, host.contains("nodeshift.space") {
            let parts = url.pathComponents.filter { $0 != "/" }
            if let index = parts.firstIndex(of: "room"), index + 1 < parts.count {
                return clean(parts[index + 1])
            }
        }
        return clean(trimmed)
    }

    private static func clean(_ text: String) -> String? {
        let upper = text.uppercased()
        let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        guard (4...8).contains(upper.count), upper.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return upper
    }

    func create() async {
        notice = nil
        do {
            let created = try await api.createRoom()
            join(code: created)
        } catch SiteError.unauthorized {
            notice = "Войди через сайт, чтобы создать комнату"
        } catch SiteError.noToken {
            notice = "Войди через сайт, чтобы создать комнату"
        } catch {
            notice = "Не получилось создать комнату"
        }
    }

    func joinChecked(code raw: String, name: String?) async -> Bool {
        notice = nil
        guard let wanted = Self.normalize(raw) else {
            notice = "Код комнаты: 6 символов, буквы и цифры"
            return false
        }
        do {
            guard try await api.roomInfo(wanted) != nil else {
                notice = "Такой комнаты нет или она закрыта"
                return false
            }
        } catch {
            notice = "Не получилось связаться с сервером"
            return false
        }
        join(code: wanted, name: name)
        return true
    }

    func join(code wanted: String, name: String? = nil) {
        if code != nil {
            leave()
        }
        closedByUser = false
        retries = 0
        notice = nil
        guestName = (name ?? Self.savedGuestName()).trimmingCharacters(in: .whitespacesAndNewlines)
        roomQueue = []
        lastState = nil
        members = []
        you = nil
        code = wanted
        status = .connecting
        player?.endedHandler = { [weak self] in
            self?.handleLocalEnded() ?? false
        }
        previous = snapshot()
        watchPlayer()
        connect(wanted)
    }

    func leave() {
        closedByUser = true
        stopTimers()
        reconnectWork?.cancel()
        reconnectWork = nil
        applyToken += 1
        let current = socket
        socket = nil
        current?.cancel(with: .goingAway, reason: nil)
        player?.endedHandler = nil
        roomQueue = []
        lastState = nil
        previous = nil
        code = nil
        members = []
        you = nil
        status = .idle
    }

    private func serverNow() -> Double {
        Date().timeIntervalSince1970 * 1000 + clockOffset
    }

    private func expectedPosition(_ state: RoomState) -> Double {
        state.playing ? state.position + (serverNow() - state.stamp) / 1000 : state.position
    }

    private func connect(_ wanted: String) {
        Task { [weak self] in
            guard let self else { return }
            let token = await self.api.freshAccessToken()
            guard !self.closedByUser, self.code == wanted, let url = self.api.roomSocketURL(wanted) else { return }
            let task = self.session.webSocketTask(with: url)
            self.socket = task
            self.bestRTT = .infinity
            task.resume()
            var hello: [String: Any] = ["type": "hello", "name": self.guestName]
            if let token {
                hello["token"] = token
            }
            self.post(hello)
            self.startTimers()
            self.receive(task, wanted: wanted)
        }
    }

    private func receive(_ task: URLSessionWebSocketTask, wanted: String) {
        Task { [weak self] in
            while true {
                do {
                    let message = try await task.receive()
                    guard let self, self.socket === task else { return }
                    switch message {
                    case let .string(text):
                        self.handle(text)
                    case let .data(data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handle(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    self?.socketClosed(task, wanted: wanted)
                    return
                }
            }
        }
    }

    private func socketClosed(_ task: URLSessionWebSocketTask, wanted: String) {
        guard socket === task else { return }
        stopTimers()
        socket = nil
        if closedByUser {
            return
        }
        if retries >= Self.maxRetries {
            toasts?.show("Связь с комнатой потеряна")
            leave()
            return
        }
        retries += 1
        status = .reconnecting
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.closedByUser, self.code == wanted else { return }
            self.connect(wanted)
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + min(Double(retries), 8), execute: work)
    }

    private func post(_ message: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        Task {
            try? await socket.send(.string(text))
        }
    }

    private func handle(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        switch type {
        case "welcome":
            retries = 0
            awaitingFirstState = true
            status = .live
            you = json["you"] as? String
        case "members":
            members = Self.parseMembers(json["members"])
        case "queue":
            roomQueue = Self.decodeTracks(json["tracks"])
        case "state":
            handleState(json)
        case "pong":
            handlePong(json)
        case "error":
            let reason = json["reason"] as? String
            toasts?.show(reason == "full" ? "В комнате нет мест" : "Комната закрыта или не найдена")
            leave()
        default:
            break
        }
    }

    private func handlePong(_ json: [String: Any]) {
        guard let sent = Self.number(json["t"]), let server = Self.number(json["server"]) else { return }
        let now = Date().timeIntervalSince1970 * 1000
        let rtt = now - sent
        if rtt <= bestRTT + 30 {
            bestRTT = min(bestRTT, rtt)
            clockOffset = server - (sent + now) / 2
        }
    }

    private func handleState(_ json: [String: Any]) {
        let id: String?
        if let number = json["track_id"] as? Int {
            id = String(number)
        } else {
            id = json["track_id"] as? String
        }
        let state = RoomState(
            index: Int(Self.number(json["index"]) ?? -1),
            trackID: id,
            playing: json["playing"] as? Bool ?? false,
            position: Self.number(json["position"]) ?? 0,
            stamp: Self.number(json["stamp"]) ?? 0,
            repeatMode: json["repeat"] as? String ?? "off",
            shuffle: json["shuffle"] as? Bool ?? false,
            by: json["by"] as? String
        )
        stateCount += 1
        if awaitingFirstState {
            awaitingFirstState = false
            if state.trackID == nil, let current = player?.current, current.siteId != nil {
                lastState = state
                sendQueue(keep: false)
                return
            }
        }
        if let by = state.by, by == you {
            lastState = state
            return
        }
        apply(state)
    }

    private func apply(_ state: RoomState) {
        lastState = state
        guard let player, let catalog, roomQueue.indices.contains(state.index) else { return }
        applyToken += 1
        let token = applyToken
        let records = roomQueue.map { catalog.record(for: $0) }
        let target = records[state.index]
        silently {
            let same = player.current?.siteId == target.siteId
            if !same {
                player.play(target, in: records)
            } else if player.queue.map({ $0.siteId ?? $0.id }) != records.map({ $0.siteId ?? $0.id }) || player.currentIndex != state.index {
                player.queue = records
                player.currentIndex = state.index
            }
            if player.isPlaying != state.playing {
                if state.playing {
                    player.resume()
                } else {
                    player.pause()
                }
            }
            if player.repeatMode.rawValue != state.repeatMode, let mode = RepeatMode(rawValue: state.repeatMode) {
                player.repeatMode = mode
            }
            if player.shuffle != state.shuffle {
                player.shuffle = state.shuffle
            }
        }
        syncPosition(state, token: token, waited: 0)
    }

    private func syncPosition(_ state: RoomState, token: Int, waited: Double) {
        guard token == applyToken, let player else { return }
        if player.engineDuration <= 0 && waited < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.syncPosition(state, token: token, waited: waited + 0.15)
            }
            return
        }
        let target = expectedPosition(state)
        silently {
            if abs(player.engineTime - target) > Self.seekTolerance {
                player.seek(to: max(0, target))
            }
            if state.playing && !player.isPlaying {
                player.resume()
            }
        }
    }

    private func startTimers() {
        stopTimers()
        let ping = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendPing()
            }
        }
        RunLoop.main.add(ping, forMode: .common)
        pingTimer = ping
        for step in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(step) * 0.4) { [weak self] in
                self?.sendPing()
            }
        }
        let drift = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.correctDrift()
            }
        }
        RunLoop.main.add(drift, forMode: .common)
        driftTimer = drift
    }

    private func stopTimers() {
        pingTimer?.invalidate()
        pingTimer = nil
        driftTimer?.invalidate()
        driftTimer = nil
    }

    private func sendPing() {
        post(["type": "ping", "t": Date().timeIntervalSince1970 * 1000])
    }

    private func correctDrift() {
        guard let state = lastState, state.playing, let player, player.engineDuration > 0, player.isPlaying else { return }
        guard player.current?.siteId == state.trackID else { return }
        let target = expectedPosition(state)
        if abs(player.engineTime - target) > Self.driftTolerance {
            silently {
                player.seek(to: max(0, target))
            }
        }
    }

    private func silently(_ block: () -> Void) {
        silent += 1
        block()
        silent -= 1
        previous = snapshot()
    }

    private func snapshot() -> PlayerSnapshot? {
        guard let player else { return nil }
        return PlayerSnapshot(
            siteID: player.current?.siteId,
            queueIDs: player.queue.map { $0.siteId ?? $0.id },
            index: player.currentIndex,
            playing: player.isPlaying,
            seekToken: player.seekToken,
            shuffle: player.shuffle,
            repeatMode: player.repeatMode
        )
    }

    private func watchPlayer() {
        guard let player, code != nil else { return }
        withObservationTracking {
            _ = player.current?.id
            _ = player.queue.count
            _ = player.currentIndex
            _ = player.isPlaying
            _ = player.seekToken
            _ = player.shuffle
            _ = player.repeatMode
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.playerChanged()
                self?.watchPlayer()
            }
        }
    }

    private func roomIndex() -> Int {
        lastState?.index ?? player?.currentIndex ?? -1
    }

    private func sharedQueue() -> (ids: [Int], index: Int)? {
        guard let player else { return nil }
        var ids: [Int] = []
        var mapped = -1
        for (position, track) in player.queue.enumerated() {
            guard let siteID = track.siteId, let number = Int(siteID) else { continue }
            ids.append(number)
            if position == player.currentIndex {
                mapped = ids.count - 1
            }
        }
        guard mapped >= 0 else { return nil }
        return (ids, mapped)
    }

    private func sendQueue(keep: Bool) {
        guard let player, let shared = sharedQueue() else { return }
        post([
            "type": "set_queue",
            "ids": shared.ids,
            "index": shared.index,
            "keep": keep,
            "position": player.engineTime,
            "playing": player.isPlaying,
        ])
    }

    private func playerChanged() {
        guard status == .live, silent == 0, let player else {
            previous = snapshot()
            return
        }
        let now = snapshot()
        guard let before = previous, let after = now, before != after else {
            previous = now
            return
        }
        previous = now
        if after.siteID != before.siteID, player.current != nil {
            guard after.siteID != nil else {
                toasts?.show("Этот трек есть только на телефоне, в комнату его не отправить")
                return
            }
            let ids = roomQueue.map { $0.id.value }
            let shared = sharedQueue()
            if let shared, shared.ids.map(String.init) == ids {
                post(["type": "jump", "index": shared.index])
            } else {
                sendQueue(keep: false)
            }
            return
        }
        if after.queueIDs != before.queueIDs, player.current != nil {
            sendQueue(keep: true)
        }
        if after.playing != before.playing, player.current != nil {
            post(["type": after.playing ? "play" : "pause", "position": player.engineTime])
        }
        if after.seekToken != before.seekToken {
            post(["type": "seek", "position": player.position])
        }
        if after.repeatMode != before.repeatMode {
            post(["type": "repeat", "mode": after.repeatMode.rawValue])
        }
        if after.shuffle != before.shuffle {
            post(["type": "shuffle", "on": after.shuffle])
        }
    }

    private func handleLocalEnded() -> Bool {
        guard status == .live, let player, player.current?.siteId != nil else {
            return false
        }
        let before = stateCount
        post(["type": "ended", "index": roomIndex()])
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.stateCount == before, self.code != nil else { return }
            self.player?.next()
        }
        return true
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return value as? Double
    }

    private static func parseMembers(_ raw: Any?) -> [RoomMember] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return RoomMember(id: id, name: item["name"] as? String ?? "Слушатель", userID: item["user_id"] as? Int)
        }
    }

    static func decodeTracks(_ raw: Any?) -> [SiteTrack] {
        guard let list = raw as? [[String: Any]] else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return list.compactMap { item in
            guard let data = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return try? decoder.decode(SiteTrack.self, from: data)
        }
    }
}
