import XCTest
@testable import NSMCore

final class AmbientMotionTests: XCTestCase {
    func testKeyframesHitStartMiddleEnd() {
        for blob in AmbientMotion.blobs {
            XCTAssertEqual(AmbientMotion.state(blob, at: 0), blob.start)
            XCTAssertEqual(AmbientMotion.state(blob, at: blob.duration / 2).x, blob.middle.x, accuracy: 1e-9)
            XCTAssertEqual(AmbientMotion.state(blob, at: blob.duration / 2).scale, blob.middle.scale, accuracy: 1e-9)
            XCTAssertEqual(AmbientMotion.state(blob, at: blob.duration).x, blob.end.x, accuracy: 1e-9)
            XCTAssertEqual(AmbientMotion.state(blob, at: blob.duration * 2).y, blob.start.y, accuracy: 1e-9)
        }
    }

    func testMotionIsContinuousAcrossIterations() {
        let blob = AmbientMotion.blobs[0]
        let before = AmbientMotion.state(blob, at: blob.duration - 0.001)
        let after = AmbientMotion.state(blob, at: blob.duration + 0.001)
        XCTAssertEqual(before.x, after.x, accuracy: 1e-3)
        XCTAssertEqual(before.scale, after.scale, accuracy: 1e-3)
    }

    func testRateFromBpm() {
        XCTAssertEqual(AmbientMotion.rate(forBpm: 92, playing: true), 0.92, accuracy: 1e-9)
        XCTAssertEqual(AmbientMotion.rate(forBpm: 200, playing: true), 1.6, accuracy: 1e-9)
        XCTAssertEqual(AmbientMotion.rate(forBpm: 40, playing: true), 0.6, accuracy: 1e-9)
        XCTAssertEqual(AmbientMotion.rate(forBpm: 0, playing: true), 0.92, accuracy: 1e-9)
        XCTAssertEqual(AmbientMotion.rate(forBpm: 120, playing: false), 0.12, accuracy: 1e-9)
    }
}
