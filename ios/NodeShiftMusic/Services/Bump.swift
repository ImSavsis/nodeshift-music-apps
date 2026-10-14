import CoreMotion
import Foundation
import Observation
import UIKit

final class BumpDetector: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private var lastBump = Date.distantPast
    private let bootTime = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    var onBump: (@Sendable (Date) -> Void)?

    init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
    }

    var isAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 100.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.userAcceleration
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            let moment = Date(timeIntervalSince1970: self.bootTime + data.timestamp)
            if magnitude > 2.4, moment.timeIntervalSince(self.lastBump) > 1.2 {
                self.lastBump = moment
                self.onBump?(moment)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

struct BumpResult: Decodable, Sendable {
    struct Peer: Decodable, Sendable {
        let name: String?
        let platform: String?
    }

    let matched: Bool
    let pair: String?
    let role: String?
    let error: String?
    let peer: Peer?
}

@MainActor
@Observable
final class BumpSession {
    enum Phase: Equatable {
        case idle
        case listening
        case matching
        case joining(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var detectorAvailable = true

    @ObservationIgnored private let detector = BumpDetector()
    @ObservationIgnored private var offsetMs = 0.0
    @ObservationIgnored private var deadline = Date.distantPast
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var onCode: ((String) -> Void)?
    @ObservationIgnored private let api = SiteAPI.shared
    @ObservationIgnored private weak var site: SiteSession?

    static var deviceID: String {
        if let saved = UserDefaults.standard.string(forKey: "nsm_device_id") {
            return saved
        }
        let fresh = UUID().uuidString.lowercased()
        UserDefaults.standard.set(fresh, forKey: "nsm_device_id")
        return fresh
    }

    func start(site: SiteSession, onCode: @escaping (String) -> Void) {
        self.site = site
        self.onCode = onCode
        deadline = Date().addingTimeInterval(90)
        phase = .listening
        detectorAvailable = detector.isAvailable
        detector.onBump = { [weak self] moment in
            Task { @MainActor in
                await self?.submit(impact: moment)
            }
        }
        detector.start()
        Task { await syncClock() }
    }

    func stop() {
        detector.stop()
        detector.onBump = nil
        onCode = nil
        phase = .idle
        busy = false
    }

    func triggerManually() {
        Task { await submit(impact: Date()) }
    }

    private func bumpURL(_ path: String) -> URL {
        api.bumpBase.appendingPathComponent(path)
    }

    private func syncClock() async {
        var best = Double.infinity
        for _ in 0..<4 {
            let sent = Date().timeIntervalSince1970 * 1000
            guard let (data, _) = try? await Net.session.data(from: bumpURL("time")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let server = (json["now"] as? NSNumber)?.doubleValue else { continue }
            let received = Date().timeIntervalSince1970 * 1000
            let rtt = received - sent
            if rtt < best {
                best = rtt
                offsetMs = server - (sent + received) / 2
            }
        }
    }

    private func submit(impact: Date) async {
        guard phase == .listening, !busy, Date() < deadline else { return }
        busy = true
        phase = .matching
        defer { busy = false }
        var request = Net.request(bumpURL("bump"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "device": Self.deviceID,
            "impact_ms": impact.timeIntervalSince1970 * 1000,
            "offset_ms": offsetMs,
            "name": site?.user?.username ?? site?.user?.handle ?? UIDevice.current.name,
            "platform": "ios",
            "can_host": site?.isLoggedIn == true,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await Net.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(BumpResult.self, from: data) else {
            phase = .listening
            return
        }
        guard result.matched else {
            phase = .listening
            return
        }
        if result.error == "login_required" {
            phase = .failed("Войди через сайт хотя бы на одном из телефонов")
            detector.stop()
            return
        }
        guard let pair = result.pair, let role = result.role else {
            phase = .listening
            return
        }
        phase = .joining(result.peer?.name ?? "телефон")
        detector.stop()
        if role == "host" {
            await host(pair: pair)
        } else {
            await guest(pair: pair)
        }
    }

    private func host(pair: String) async {
        do {
            let code = try await api.createRoom()
            var request = Net.request(bumpURL("pair/\(pair)/room"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["device": Self.deviceID, "code": code])
            _ = try? await Net.session.data(for: request)
            finish(code)
        } catch {
            phase = .failed("Не получилось создать комнату")
        }
    }

    private func guest(pair: String) async {
        var link = URLComponents(url: bumpURL("pair/\(pair)/room"), resolvingAgainstBaseURL: false)
        link?.queryItems = [URLQueryItem(name: "device", value: Self.deviceID), URLQueryItem(name: "wait", value: "15")]
        guard let url = link?.url else {
            phase = .failed("Не получилось присоединиться")
            return
        }
        var request = Net.request(url)
        request.timeoutInterval = 25
        guard let (data, response) = try? await Net.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String else {
            phase = .failed("Второй телефон не создал комнату")
            return
        }
        finish(code)
    }

    private func finish(_ code: String) {
        let handler = onCode
        stop()
        handler?(code)
    }
}
