import UIKit
import XCTest
@testable import NodeShiftMusic

final class PresenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(
        playing: Bool = true,
        position: Int = 10_000,
        duration: Int = 200_000,
        cover: String? = "https://burmalda.savsis.xyz/covers/a.jpg",
        title: String = "Song"
    ) -> PresenceSnapshot {
        PresenceSnapshot(
            device: "dev-1",
            platform: "ios",
            playing: playing,
            title: title,
            artist: "Artist",
            album: "Album",
            positionMs: position,
            durationMs: duration,
            cover: cover,
            siteId: "53"
        )
    }

    private func object(_ payload: PresencePayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testBackoffFollowsTheAgreedSchedule() {
        let backoff = Backoff.standard
        XCTAssertEqual((1...7).map { backoff.delay(afterFailures: $0) }, [2, 4, 8, 16, 30, 30, 30])
        XCTAssertEqual(backoff.delay(afterFailures: 0), 2)
        XCTAssertEqual(backoff.delay(afterFailures: -3), 2)
        XCTAssertEqual(backoff.attempts, 6)
        XCTAssertEqual(Backoff(steps: []).delay(afterFailures: 4), 0)
    }

    func testGateSendsFirstSnapshotAndForcedOnes() {
        var gate = PresenceGate()
        let first = snapshot()
        XCTAssertTrue(gate.shouldSend(first, at: start, force: false))
        gate.recordSent(first, at: start)
        XCTAssertFalse(gate.shouldSend(first, at: start, force: false))
        XCTAssertTrue(gate.shouldSend(first, at: start, force: true))
    }

    func testGateIgnoresPositionThatMatchesPlayback() {
        var gate = PresenceGate()
        gate.recordSent(snapshot(position: 10_000), at: start)
        let later = start.addingTimeInterval(8)
        XCTAssertFalse(gate.shouldSend(snapshot(position: 18_300), at: later, force: false))
        XCTAssertFalse(gate.shouldSend(snapshot(position: 20_400), at: later, force: false))
    }

    func testGateSendsWhenPositionJumps() {
        var gate = PresenceGate()
        gate.recordSent(snapshot(position: 10_000), at: start)
        let later = start.addingTimeInterval(8)
        XCTAssertTrue(gate.shouldSend(snapshot(position: 60_000), at: later, force: false))
        XCTAssertTrue(gate.shouldSend(snapshot(position: 3_000), at: later, force: false))
        XCTAssertTrue(gate.shouldSend(snapshot(position: 21_000), at: later, force: false))
    }

    func testGateExpectsFrozenPositionWhilePaused() {
        var gate = PresenceGate()
        gate.recordSent(snapshot(playing: false, position: 42_000), at: start)
        let later = start.addingTimeInterval(120)
        XCTAssertFalse(gate.shouldSend(snapshot(playing: false, position: 42_800), at: later, force: false))
        XCTAssertTrue(gate.shouldSend(snapshot(playing: false, position: 47_000), at: later, force: false))
    }

    func testGateSendsOnAnyContentChange() {
        var gate = PresenceGate()
        gate.recordSent(snapshot(), at: start)
        XCTAssertTrue(gate.shouldSend(snapshot(playing: false), at: start, force: false))
        XCTAssertTrue(gate.shouldSend(snapshot(duration: 0), at: start, force: false))
        XCTAssertTrue(gate.shouldSend(snapshot(cover: nil), at: start, force: false))
        XCTAssertTrue(gate.shouldSend(snapshot(title: "Other"), at: start, force: false))
    }

    func testGateClampsExpectedPositionToDuration() {
        var gate = PresenceGate()
        gate.recordSent(snapshot(position: 199_000, duration: 200_000), at: start)
        let later = start.addingTimeInterval(60)
        XCTAssertFalse(gate.shouldSend(snapshot(position: 200_000, duration: 200_000), at: later, force: false))
    }

    func testGateResetForgetsWhatWasSent() {
        var gate = PresenceGate()
        gate.recordSent(snapshot(), at: start)
        gate.reset()
        XCTAssertTrue(gate.shouldSend(snapshot(), at: start, force: false))
    }

    func testCoverBlockLastsFiveMinutesPerCover() {
        var blocks = PresenceCoverBlocks()
        XCTAssertFalse(blocks.isBlocked("a.jpg", at: start))
        blocks.block("a.jpg", from: start)
        XCTAssertTrue(blocks.isBlocked("a.jpg", at: start.addingTimeInterval(1)))
        XCTAssertTrue(blocks.isBlocked("a.jpg", at: start.addingTimeInterval(299)))
        XCTAssertFalse(blocks.isBlocked("a.jpg", at: start.addingTimeInterval(300)))
        XCTAssertFalse(blocks.isBlocked("b.jpg", at: start.addingTimeInterval(1)))
    }

    func testCoverBlockRestartsAfterAnotherFailure() {
        var blocks = PresenceCoverBlocks()
        blocks.block("a.jpg", from: start)
        let second = start.addingTimeInterval(400)
        XCTAssertFalse(blocks.isBlocked("a.jpg", at: second))
        blocks.block("a.jpg", from: second)
        XCTAssertTrue(blocks.isBlocked("a.jpg", at: second.addingTimeInterval(200)))
        XCTAssertFalse(blocks.isBlocked("a.jpg", at: second.addingTimeInterval(301)))
    }

    func testCoverRulesAcceptOnlyHttps() {
        XCTAssertEqual(PresenceCoverRules.https("https://burmalda.savsis.xyz/covers/a.jpg"), "https://burmalda.savsis.xyz/covers/a.jpg")
        XCTAssertNil(PresenceCoverRules.https("http://burmalda.savsis.xyz/covers/a.jpg"))
        XCTAssertNil(PresenceCoverRules.https("file:///var/mobile/a.jpg"))
        XCTAssertNil(PresenceCoverRules.https(""))
        XCTAssertNil(PresenceCoverRules.https(nil))
    }

    func testCoverFreshnessFollowsTheAgeOfTheUpload() {
        let day: TimeInterval = 86400
        XCTAssertEqual(PresenceCoverRules.freshness(uploadedAt: start, now: start.addingTimeInterval(29 * day)), .fresh)
        XCTAssertEqual(PresenceCoverRules.freshness(uploadedAt: start, now: start.addingTimeInterval(30 * day)), .stale)
        XCTAssertEqual(PresenceCoverRules.freshness(uploadedAt: start, now: start.addingTimeInterval(74 * day)), .stale)
        XCTAssertEqual(PresenceCoverRules.freshness(uploadedAt: start, now: start.addingTimeInterval(75 * day)), .expired)
        XCTAssertEqual(PresenceCoverRules.freshness(uploadedAt: nil, now: start), .stale)
        XCTAssertEqual(PresenceCoverRules.freshness(uploadedAt: start.addingTimeInterval(day), now: start), .fresh)
    }

    func testSnapshotIsBuiltFromLiveStateOnly() throws {
        var track = TrackRecord.blank(id: "t1")
        track.title = "  Song  "
        track.artist = "Artist"
        track.siteId = "53"
        let built = try XCTUnwrap(PresenceSnapshot.make(
            track: track,
            device: "dev-1",
            playing: true,
            position: 12.3456,
            duration: 200,
            cover: "https://burmalda.savsis.xyz/covers/a.jpg"
        ))
        XCTAssertEqual(built.title, "Song")
        XCTAssertEqual(built.album, "")
        XCTAssertEqual(built.platform, "ios")
        XCTAssertEqual(built.positionMs, 12_345)
        XCTAssertEqual(built.durationMs, 200_000)
        XCTAssertEqual(built.siteId, "53")
    }

    func testSnapshotRejectsBlankTitleAndClampsNumbers() throws {
        var track = TrackRecord.blank(id: "t1")
        track.title = "   "
        XCTAssertNil(PresenceSnapshot.make(track: track, device: "d", playing: true, position: 1, duration: 2, cover: nil))
        track.title = "Song"
        let clamped = try XCTUnwrap(PresenceSnapshot.make(track: track, device: "d", playing: true, position: 500, duration: 200, cover: nil))
        XCTAssertEqual(clamped.positionMs, 200_000)
        let broken = try XCTUnwrap(PresenceSnapshot.make(track: track, device: "d", playing: false, position: .nan, duration: -.infinity, cover: nil))
        XCTAssertEqual(broken.positionMs, 0)
        XCTAssertEqual(broken.durationMs, 0)
    }

    func testPublishPayloadUsesProtocolKeys() throws {
        let json = try object(PresencePayload(snapshot()))
        XCTAssertEqual(Set(json.keys), ["device", "platform", "playing", "title", "artist", "album", "position_ms", "duration_ms", "cover", "site_id"])
        XCTAssertEqual(json["device"] as? String, "dev-1")
        XCTAssertEqual(json["playing"] as? Bool, true)
        XCTAssertEqual(json["position_ms"] as? Int, 10_000)
        XCTAssertEqual(json["duration_ms"] as? Int, 200_000)
        XCTAssertNil(json["stop"])
    }

    func testPublishPayloadOmitsMissingCoverAndSiteId() throws {
        var bare = snapshot(cover: nil)
        bare.siteId = nil
        let json = try object(PresencePayload(bare))
        XCTAssertNil(json["cover"])
        XCTAssertNil(json["site_id"])
    }

    func testStopPayloadCarriesTheDevice() throws {
        let json = try object(PresencePayload.stopping(device: "dev-1"))
        XCTAssertEqual(Set(json.keys), ["stop", "device"])
        XCTAssertEqual(json["stop"] as? Bool, true)
        XCTAssertEqual(json["device"] as? String, "dev-1")
    }

    func testPayloadAdvancesOnlyWhilePlayingAndStaysInsideDuration() {
        let playing = PresencePayload(snapshot(position: 10_000, duration: 200_000))
        XCTAssertEqual(playing.advanced(by: 1_500).positionMs, 11_500)
        XCTAssertEqual(playing.advanced(by: 0).positionMs, 10_000)
        XCTAssertEqual(playing.advanced(by: 500_000).positionMs, 200_000)
        let paused = PresencePayload(snapshot(playing: false, position: 10_000))
        XCTAssertEqual(paused.advanced(by: 1_500).positionMs, 10_000)
        XCTAssertEqual(PresencePayload.stopping(device: "d").advanced(by: 1_500), PresencePayload.stopping(device: "d"))
    }

    func testStatusCodesMapToRetryDecisions() {
        XCTAssertEqual(PresenceResult.classify(status: 200), .sent)
        XCTAssertEqual(PresenceResult.classify(status: 204), .sent)
        XCTAssertEqual(PresenceResult.classify(status: 429), .failed)
        XCTAssertEqual(PresenceResult.classify(status: 503), .failed)
        XCTAssertEqual(PresenceResult.classify(status: 408), .failed)
        XCTAssertEqual(PresenceResult.classify(status: 400), .rejected)
        XCTAssertEqual(PresenceResult.classify(status: 404), .rejected)
        XCTAssertEqual(PresenceResult.classify(status: 413), .rejected)
    }

    func testInterruptionPausesAndResumesOnlyWhatItPaused() {
        var policy = InterruptionPolicy()
        let began = policy.handle(.began, isPlaying: true)
        let ended = policy.handle(.ended(shouldResume: true), isPlaying: false)
        let again = policy.handle(.ended(shouldResume: true), isPlaying: false)
        XCTAssertEqual(began, .pause)
        XCTAssertEqual(ended, .resume)
        XCTAssertEqual(again, .nothing)
    }

    func testInterruptionDoesNotResumeWithoutPermissionOrWhenAlreadyPaused() {
        var policy = InterruptionPolicy()
        let first = policy.handle(.began, isPlaying: true)
        let denied = policy.handle(.ended(shouldResume: false), isPlaying: false)
        let idleBegan = policy.handle(.began, isPlaying: false)
        let idleEnded = policy.handle(.ended(shouldResume: true), isPlaying: false)
        let second = policy.handle(.began, isPlaying: true)
        let takenOver = policy.handle(.ended(shouldResume: true), isPlaying: true)
        XCTAssertEqual(first, .pause)
        XCTAssertEqual(denied, .nothing)
        XCTAssertEqual(idleBegan, .nothing)
        XCTAssertEqual(idleEnded, .nothing)
        XCTAssertEqual(second, .pause)
        XCTAssertEqual(takenOver, .nothing)
    }

    func testArtJPEGStaysUnderTheUploadLimit() throws {
        let size = CGSize(width: 1800, height: 1800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nsm-art-\(UUID().uuidString).png")
        try XCTUnwrap(image.pngData()).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let jpeg = try XCTUnwrap(PresenceArt.jpeg(at: file))
        XCTAssertLessThanOrEqual(jpeg.count, PresenceCoverRules.maxArtBytes)
        XCTAssertEqual(jpeg.first, 0xFF)
    }

    func testArtJPEGIsNilForMissingFile() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nsm-missing-\(UUID().uuidString).jpg")
        XCTAssertNil(PresenceArt.jpeg(at: missing))
    }
}
