import XCTest
@testable import NodeShiftMusic

private final class Uploads: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0
    private var answer: String?

    init(answer: String?) {
        self.answer = answer
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return total
    }

    func record() -> String? {
        lock.lock()
        defer { lock.unlock() }
        total += 1
        return answer
    }
}

@MainActor
private final class TestClock {
    var moment: Date

    init(_ moment: Date) {
        self.moment = moment
    }
}

@MainActor
final class PresenceCoversTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86400
    private let hosted = "https://music.nodeshift.space/app/bump/presence/art/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg"
    private var suites: [String] = []

    override func tearDownWithError() throws {
        for name in suites {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        suites.removeAll()
    }

    private func store() -> UserDefaults {
        let name = "nsm-covers-tests-\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func make(_ uploads: Uploads, _ clock: TestClock, _ defaults: UserDefaults) -> PresenceCovers {
        PresenceCovers(
            upload: { _ in uploads.record() },
            load: { _ in Data([0xFF, 0xD8, 0xFF]) },
            defaults: defaults,
            now: { clock.moment }
        )
    }

    private func track(cover: String?) -> TrackRecord {
        var record = TrackRecord.blank(id: "t1")
        record.title = "Song"
        record.coverName = cover
        return record
    }

    private func seed(_ defaults: UserDefaults, uploadedAt: Date?) {
        defaults.set(["mine.jpg": hosted], forKey: PresenceCovers.storeKey)
        if let uploadedAt {
            defaults.set(["mine.jpg": uploadedAt.timeIntervalSince1970], forKey: PresenceCovers.stampKey)
        }
    }

    func testRemoteAndSiteCoversResolveWithoutUploading() async {
        let uploads = Uploads(answer: hosted)
        let covers = make(uploads, TestClock(start), store())
        XCTAssertEqual(covers.url(for: track(cover: CoverSource.remoteName("abc.jpg"))), "https://burmalda.savsis.xyz/covers/abc.jpg")
        XCTAssertEqual(covers.url(for: track(cover: "site-def.jpg")), "https://burmalda.savsis.xyz/covers/def.jpg")
        XCTAssertNil(covers.url(for: track(cover: nil)))
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(uploads.count, 0)
    }

    func testLocalCoverIsWithheldUntilItsUploadFinishes() async {
        let defaults = store()
        let uploads = Uploads(answer: hosted)
        let clock = TestClock(start)
        let covers = make(uploads, clock, defaults)
        var ready = 0
        covers.onReady = { ready += 1 }
        XCTAssertNil(covers.url(for: track(cover: "mine.jpg")))
        let landed = await eventually { ready == 1 }
        XCTAssertTrue(landed)
        XCTAssertEqual(covers.url(for: track(cover: "mine.jpg")), hosted)
        XCTAssertEqual(uploads.count, 1)
        let reloaded = make(uploads, clock, defaults)
        XCTAssertEqual(reloaded.url(for: track(cover: "mine.jpg")), hosted)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(uploads.count, 1)
    }

    func testFailedUploadIsNotRetriedWithinFiveMinutes() async {
        let uploads = Uploads(answer: nil)
        let clock = TestClock(start)
        let covers = make(uploads, clock, store())
        XCTAssertNil(covers.url(for: track(cover: "mine.jpg")))
        let tried = await eventually { uploads.count == 1 }
        XCTAssertTrue(tried)
        try? await Task.sleep(for: .milliseconds(100))
        clock.moment = start.addingTimeInterval(299)
        XCTAssertNil(covers.url(for: track(cover: "mine.jpg")))
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(uploads.count, 1)
        clock.moment = start.addingTimeInterval(301)
        XCTAssertNil(covers.url(for: track(cover: "mine.jpg")))
        let again = await eventually { uploads.count == 2 }
        XCTAssertTrue(again)
    }

    func testFreshCoverComesFromTheCacheWithoutUploading() async {
        let defaults = store()
        seed(defaults, uploadedAt: start.addingTimeInterval(-day))
        let uploads = Uploads(answer: hosted)
        let covers = make(uploads, TestClock(start), defaults)
        XCTAssertEqual(covers.url(for: track(cover: "mine.jpg")), hosted)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(uploads.count, 0)
    }

    func testStaleCoverKeepsItsUrlWhileItIsUploadedAgain() async {
        let defaults = store()
        seed(defaults, uploadedAt: start.addingTimeInterval(-40 * day))
        let uploads = Uploads(answer: hosted)
        let covers = make(uploads, TestClock(start), defaults)
        var ready = 0
        covers.onReady = { ready += 1 }
        XCTAssertEqual(covers.url(for: track(cover: "mine.jpg")), hosted)
        let refreshed = await eventually { ready == 1 }
        XCTAssertTrue(refreshed)
        XCTAssertEqual(covers.url(for: track(cover: "mine.jpg")), hosted)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(uploads.count, 1)
        let stamps = defaults.dictionary(forKey: PresenceCovers.stampKey) as? [String: Double]
        XCTAssertEqual(stamps?["mine.jpg"], start.timeIntervalSince1970)
    }

    func testExpiredCoverIsWithheldUntilItIsUploadedAgain() async {
        let defaults = store()
        seed(defaults, uploadedAt: start.addingTimeInterval(-80 * day))
        let uploads = Uploads(answer: hosted)
        let covers = make(uploads, TestClock(start), defaults)
        var ready = 0
        covers.onReady = { ready += 1 }
        XCTAssertNil(covers.url(for: track(cover: "mine.jpg")))
        let refreshed = await eventually { ready == 1 }
        XCTAssertTrue(refreshed)
        XCTAssertEqual(covers.url(for: track(cover: "mine.jpg")), hosted)
        XCTAssertEqual(uploads.count, 1)
    }

    func testCoverWithoutATimestampIsRefreshedOnce() async {
        let defaults = store()
        seed(defaults, uploadedAt: nil)
        let uploads = Uploads(answer: hosted)
        let covers = make(uploads, TestClock(start), defaults)
        var ready = 0
        covers.onReady = { ready += 1 }
        XCTAssertEqual(covers.url(for: track(cover: "mine.jpg")), hosted)
        let refreshed = await eventually { ready == 1 }
        XCTAssertTrue(refreshed)
        XCTAssertEqual(covers.url(for: track(cover: "mine.jpg")), hosted)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(uploads.count, 1)
    }
}
