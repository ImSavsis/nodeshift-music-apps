import XCTest
@testable import NSMCore

final class SVGPathTests: XCTestCase {
    func testAbsoluteAndRelativeLines() {
        let commands = SVGPath.parse("M1 2L3 4l1 1h2v-3Z")
        XCTAssertEqual(commands, [
            .move(1, 2),
            .line(3, 4),
            .line(4, 5),
            .line(6, 5),
            .line(6, 2),
            .close,
        ])
    }

    func testCompactNumbers() {
        let commands = SVGPath.parse("M19 14c1.49-1.46 3-3.21 3-5.5")
        guard case let .cubic(x1, y1, x2, y2, x, y)? = commands.last else {
            return XCTFail("expected cubic")
        }
        XCTAssertEqual(x1, 20.49, accuracy: 1e-9)
        XCTAssertEqual(y1, 12.54, accuracy: 1e-9)
        XCTAssertEqual(x2, 22, accuracy: 1e-9)
        XCTAssertEqual(y2, 10.79, accuracy: 1e-9)
        XCTAssertEqual(x, 22, accuracy: 1e-9)
        XCTAssertEqual(y, 8.5, accuracy: 1e-9)
    }

    func testImplicitLineAfterMove() {
        XCTAssertEqual(SVGPath.parse("M0 0 5 5 10 0"), [.move(0, 0), .line(5, 5), .line(10, 0)])
        XCTAssertEqual(SVGPath.parse("m1 1 2 2"), [.move(1, 1), .line(3, 3)])
    }

    func testSmoothCubicReflectsControlPoint() {
        let commands = SVGPath.parse("M0 0C1 1 2 1 3 0S5 -1 6 0")
        XCTAssertEqual(commands.count, 3)
        guard case let .cubic(x1, y1, _, _, _, _) = commands[2] else {
            return XCTFail("expected cubic")
        }
        XCTAssertEqual(x1, 4, accuracy: 1e-9)
        XCTAssertEqual(y1, -1, accuracy: 1e-9)
    }

    func testArcEndpointsLieOnCircle() {
        let commands = SVGPath.parse("M0 5A5 5 0 0 1 10 5")
        XCTAssertGreaterThanOrEqual(commands.count, 3)
        var endpoints: [(Double, Double)] = []
        for command in commands.dropFirst() {
            guard case let .cubic(_, _, _, _, x, y) = command else {
                return XCTFail("expected cubics")
            }
            endpoints.append((x, y))
        }
        for (x, y) in endpoints {
            let distance = ((x - 5) * (x - 5) + (y - 5) * (y - 5)).squareRoot()
            XCTAssertEqual(distance, 5, accuracy: 1e-6)
        }
        XCTAssertEqual(endpoints.last?.0 ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(endpoints.last?.1 ?? 0, 5, accuracy: 1e-9)
        XCTAssertLessThan(endpoints.first?.1 ?? 0, 5)
    }

    func testArcSweepDirection() {
        let up = SVGPath.parse("M0 5A5 5 0 0 1 10 5")
        let down = SVGPath.parse("M0 5A5 5 0 0 0 10 5")
        guard case let .cubic(_, _, _, _, _, upY)? = up.dropFirst().first,
              case let .cubic(_, _, _, _, _, downY)? = down.dropFirst().first else {
            return XCTFail("expected cubics")
        }
        XCTAssertLessThan(upY, 5)
        XCTAssertGreaterThan(downY, 5)
    }

    func testCompressedArcFlags() {
        let spaced = SVGPath.parse("M0 0a1 1 0 0 1 1 1")
        let compact = SVGPath.parse("M0 0a1 1 0 011 1")
        XCTAssertEqual(spaced, compact)
    }

    func testPolygonPoints() {
        let points = SVGPath.parsePoints("19 20 9 12 19 4 19 20")
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(points[1].0, 9)
        XCTAssertEqual(points[1].1, 12)
    }

    func testHeartIconParses() {
        let heart = "M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"
        let commands = SVGPath.parse(heart)
        XCTAssertEqual(commands.last, .close)
        XCTAssertGreaterThan(commands.count, 8)
    }
}
