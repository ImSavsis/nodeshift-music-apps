import XCTest
@testable import NodeShiftMusic

@MainActor
private final class RecordingSink: PresenceSink {
    var scripted: [PresenceResult] = []
    var published: [PresenceSnapshot] = []
    var clears = 0
    var detachedClears = 0
    var inFlight = 0
    var peak = 0
    var holdNext = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func publish(_ snapshot: PresenceSnapshot) async -> PresenceResult {
        inFlight += 1
        peak = max(peak, inFlight)
        published.append(snapshot)
        if holdNext {
            holdNext = false
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiting.append(continuation)
            }
        }
        inFlight -= 1
        return scripted.isEmpty ? .sent : scripted.removeFirst()
    }

    func clear() async -> PresenceResult {
        clears += 1
        return .sent
    }

    func clearDetached() {
        detachedClears += 1
    }

    func release() {
        let pending = waiting
        waiting.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

@MainActor
private final class EnabledFlag {
    var on = true
}

@MainActor
private final class Rig {
    let sink: RecordingSink
    let flag: EnabledFlag
    let player = PlayerStore()
    let site = SiteSession()
    let reporter: PresenceReporter
    private let suite: String

    init(backoff: Backoff = Backoff(steps: [0.02]), startHold: TimeInterval = 0) {
        let sink = RecordingSink()
        let flag = EnabledFlag()
        let name = "nsm-reporter-tests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        self.sink = sink
        self.flag = flag
        self.suite = name
        reporter = PresenceReporter(
            sink: sink,
            covers: PresenceCovers(upload: { _ in nil }, defaults: store),
            deviceID: "dev-1",
            isEnabled: { flag.on },
            backoff: backoff,
            startHold: startHold
        )
    }

    static func track() -> TrackRecord {
        var record = TrackRecord.blank(id: "t1")
        record.title = "Song"
        record.artist = "Artist"
        record.durationMs = 200_000
        return record
    }

    func begin() {
        let item = Self.track()
        player.play(item, in: [item])
        reporter.attach(player: player, site: site)
    }

    func finish() {
        player.pause()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}

@MainActor
final class PresenceReporterTests: XCTestCase {
    func testBurstKeepsOneRequestInFlightAndTheLastStateWins() async {
        let rig = Rig()
        defer { rig.finish() }
        rig.sink.holdNext = true
        rig.begin()
        let first = await eventually { rig.sink.published.count == 1 }
        XCTAssertTrue(first)
        rig.player.seek(to: 30)
        rig.player.seek(to: 60)
        rig.player.seek(to: 90)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(rig.sink.published.count, 1)
        rig.sink.release()
        let second = await eventually { rig.sink.published.count == 2 }
        XCTAssertTrue(second)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(rig.sink.published.count, 2)
        XCTAssertEqual(rig.sink.peak, 1)
        XCTAssertLessThan(rig.sink.published[0].positionMs, 5_000)
        XCTAssertGreaterThanOrEqual(rig.sink.published[1].positionMs, 90_000)
    }

    func testFailedPublishIsRetriedUntilItGoesThrough() async {
        let rig = Rig()
        defer { rig.finish() }
        rig.sink.scripted = [.failed, .failed]
        rig.begin()
        let landed = await eventually { rig.sink.published.count == 3 }
        XCTAssertTrue(landed)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(rig.sink.published.count, 3)
        XCTAssertEqual(Set(rig.sink.published.map { $0.title }), ["Song"])
        XCTAssertEqual(rig.sink.peak, 1)
    }

    func testNewStateSupersedesAPendingRetry() async {
        let rig = Rig(backoff: Backoff(steps: [30]))
        defer { rig.finish() }
        rig.sink.scripted = [.failed]
        rig.begin()
        let failed = await eventually { rig.sink.published.count == 1 }
        XCTAssertTrue(failed)
        try? await Task.sleep(for: .milliseconds(100))
        rig.player.pause()
        let superseded = await eventually { rig.sink.published.count == 2 }
        XCTAssertTrue(superseded)
        XCTAssertEqual(rig.sink.published[1].playing, false)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(rig.sink.published.count, 2)
    }

    func testDisablingPresenceClearsTheHubExactlyOnce() async {
        let rig = Rig()
        defer { rig.finish() }
        rig.begin()
        let sent = await eventually { rig.sink.published.count == 1 }
        XCTAssertTrue(sent)
        try? await Task.sleep(for: .milliseconds(50))
        rig.flag.on = false
        rig.reporter.reconcile()
        let cleared = await eventually { rig.sink.clears == 1 }
        XCTAssertTrue(cleared)
        rig.player.seek(to: 20)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(rig.sink.clears, 1)
        XCTAssertEqual(rig.sink.published.count, 1)
    }

    func testStopNowSendsTheDetachedStopOnlyAfterSomethingWasPublished() async {
        let rig = Rig()
        defer { rig.finish() }
        rig.reporter.attach(player: rig.player, site: rig.site)
        rig.reporter.stopNow()
        XCTAssertEqual(rig.sink.detachedClears, 0)
        let item = Rig.track()
        rig.player.play(item, in: [item])
        let sent = await eventually { rig.sink.published.count == 1 }
        XCTAssertTrue(sent)
        try? await Task.sleep(for: .milliseconds(50))
        rig.flag.on = false
        rig.reporter.stopNow()
        XCTAssertEqual(rig.sink.detachedClears, 1)
        rig.reporter.reconcile()
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(rig.sink.published.count, 1)
        XCTAssertEqual(rig.sink.clears, 0)
    }

    func testTrackStartWaitsUntilPlaybackHasAdvanced() async {
        let rig = Rig(startHold: 3)
        defer { rig.finish() }
        rig.begin()
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(rig.sink.published.count, 0)
        rig.player.position = 4
        let sent = await eventually { rig.sink.published.count == 1 }
        XCTAssertTrue(sent)
        XCTAssertGreaterThanOrEqual(rig.sink.published[0].positionMs, 4_000)
    }

    func testTrackStartIsPublishedAnywayWhenPlaybackNeverAdvances() async {
        let rig = Rig(startHold: 0.3)
        defer { rig.finish() }
        rig.begin()
        let sent = await eventually { rig.sink.published.count == 1 }
        XCTAssertTrue(sent)
        XCTAssertLessThan(rig.sink.published[0].positionMs, 3_000)
        XCTAssertEqual(rig.sink.published[0].playing, true)
    }
}
