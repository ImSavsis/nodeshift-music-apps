import XCTest
@testable import NSMCore

final class CoverMotionTests: XCTestCase {
    private struct SeedCase: Decodable {
        let seed: String
        let hash: UInt32
        let duration: Double
        let delay: Double
        let shiftX: Double
        let shiftY: Double
        let originX: Double
        let originY: Double
        let sheenDelay: Double
    }

    private struct EasingCase: Decodable {
        struct Sample: Decodable {
            let x: Double
            let y: Double
        }

        let curve: [Double]
        let samples: [Sample]
    }

    func testSeedsMatchSiteHash() throws {
        let cases = try JSONDecoder().decode([SeedCase].self, from: TestData.data("cover-seeds.json"))
        XCTAssertGreaterThan(cases.count, 8)
        for item in cases {
            XCTAssertEqual(CoverMotion.hash(item.seed), item.hash, item.seed)
            let drift = CoverMotion.drift(seed: item.seed)
            XCTAssertEqual(drift.duration, item.duration, accuracy: 1e-9, item.seed)
            XCTAssertEqual(drift.delay, item.delay, accuracy: 1e-9, item.seed)
            XCTAssertEqual(drift.shiftX, item.shiftX, accuracy: 1e-9, item.seed)
            XCTAssertEqual(drift.shiftY, item.shiftY, accuracy: 1e-9, item.seed)
            XCTAssertEqual(drift.originX, item.originX, accuracy: 1e-9, item.seed)
            XCTAssertEqual(drift.originY, item.originY, accuracy: 1e-9, item.seed)
            XCTAssertEqual(drift.sheenDelay, item.sheenDelay, accuracy: 1e-9, item.seed)
        }
    }

    func testEasingMatchesReference() throws {
        let cases = try JSONDecoder().decode([EasingCase].self, from: TestData.data("easing.json"))
        XCTAssertEqual(cases.count, 4)
        for item in cases {
            let curve = CubicBezier(item.curve[0], item.curve[1], item.curve[2], item.curve[3])
            for sample in item.samples {
                XCTAssertEqual(curve.value(at: sample.x), sample.y, accuracy: 1e-7, "\(item.curve) @ \(sample.x)")
            }
        }
    }

    func testEasingIsMonotonicForEaseInOut() {
        var previous = -1.0
        for step in 0...100 {
            let value = CubicBezier.easeInOut.value(at: Double(step) / 100)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
        XCTAssertEqual(CubicBezier.easeInOut.value(at: 0.5), 0.5, accuracy: 1e-9)
    }

    func testDriftProgressAlternates() {
        let drift = CoverDrift(duration: 20, delay: -5, shiftX: 2, shiftY: 1, originX: 50, originY: 50, sheenDelay: 0)
        XCTAssertEqual(CoverMotion.driftProgress(time: 0, drift: drift), CubicBezier.easeInOut.value(at: 0.25), accuracy: 1e-9)
        XCTAssertEqual(CoverMotion.driftProgress(time: 15, drift: drift), 1, accuracy: 1e-9)
        XCTAssertEqual(CoverMotion.driftProgress(time: 20, drift: drift), CubicBezier.easeInOut.value(at: 0.75), accuracy: 1e-9)
        XCTAssertEqual(CoverMotion.driftProgress(time: 25, drift: drift), 0.5, accuracy: 1e-9)
        XCTAssertEqual(CoverMotion.driftProgress(time: 35, drift: drift), 0, accuracy: 1e-9)
        XCTAssertEqual(CoverMotion.driftScale(progress: 0), 1.02, accuracy: 1e-12)
        XCTAssertEqual(CoverMotion.driftScale(progress: 1), 1.14, accuracy: 1e-12)
    }

    func testSheenRestsThenSweeps() {
        let drift = CoverDrift(duration: 20, delay: 0, shiftX: 0, shiftY: 0, originX: 50, originY: 50, sheenDelay: 0)
        XCTAssertEqual(CoverMotion.sheenOffset(time: 0, drift: drift), -1.3, accuracy: 1e-12)
        XCTAssertEqual(CoverMotion.sheenOffset(time: 5, drift: drift), -1.3, accuracy: 1e-12)
        XCTAssertEqual(CoverMotion.sheenOffset(time: 9 * 0.81, drift: drift), 0, accuracy: 1e-9)
        XCTAssertEqual(CoverMotion.sheenOffset(time: 8.999, drift: drift), 1.3, accuracy: 1e-3)
    }
}
