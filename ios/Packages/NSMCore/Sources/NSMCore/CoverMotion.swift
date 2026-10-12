import Foundation

public struct CubicBezier: Equatable, Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    public static let easeInOut = CubicBezier(0.42, 0, 0.58, 1)
    public static let expoOut = CubicBezier(0.16, 1, 0.3, 1)

    private func sample(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    public func value(at x: Double) -> Double {
        if x <= 0 {
            return 0
        }
        if x >= 1 {
            return 1
        }
        var low = 0.0
        var high = 1.0
        var t = x
        for _ in 0..<60 {
            let current = sample(x1, x2, t)
            if abs(current - x) < 1e-12 {
                break
            }
            if current < x {
                low = t
            } else {
                high = t
            }
            t = (low + high) / 2
        }
        return sample(y1, y2, t)
    }
}

public struct CoverDrift: Equatable, Sendable {
    public var duration: Double
    public var delay: Double
    public var shiftX: Double
    public var shiftY: Double
    public var originX: Double
    public var originY: Double
    public var sheenDelay: Double
}

public enum CoverMotion {
    public static let sheenPeriod = 9.0
    public static let driftScaleFrom = 1.02
    public static let driftScaleTo = 1.14

    public static func hash(_ text: String) -> UInt32 {
        var value: UInt32 = 0
        for unit in text.utf16 {
            value = value &* 31 &+ UInt32(unit)
        }
        return value
    }

    public static func drift(seed: String) -> CoverDrift {
        let h = hash(seed)
        let signed = Int32(truncatingIfNeeded: h)
        func shifted(_ bits: Int32) -> Int {
            Int(signed >> bits)
        }
        let unsigned = Int(h)
        let signX: Double = (h & 1) != 0 ? 1 : -1
        let signY: Double = (h & 2) != 0 ? 1 : -1
        return CoverDrift(
            duration: Double(18 + unsigned % 13),
            delay: -Double(shifted(4) % 20),
            shiftX: signX * (1.5 + Double(unsigned % 3) * 0.6),
            shiftY: signY * (1 + Double(shifted(2) % 3) * 0.5),
            originX: Double(30 + shifted(8) % 40),
            originY: Double(30 + shifted(12) % 40),
            sheenDelay: -Double(shifted(6) % 9)
        )
    }

    public static func driftProgress(time: Double, drift: CoverDrift) -> Double {
        let local = time - drift.delay
        if local <= 0 {
            return 0
        }
        let cycles = local / drift.duration
        let iteration = Int(cycles.rounded(.down))
        var u = cycles - Double(iteration)
        if iteration % 2 == 1 {
            u = 1 - u
        }
        return CubicBezier.easeInOut.value(at: u)
    }

    public static func driftScale(progress: Double) -> Double {
        driftScaleFrom + (driftScaleTo - driftScaleFrom) * progress
    }

    public static func sheenOffset(time: Double, drift: CoverDrift) -> Double {
        let local = time - drift.sheenDelay
        let cycles = local / sheenPeriod
        let u = cycles - cycles.rounded(.down)
        if u < 0.62 {
            return -1.3
        }
        return -1.3 + 2.6 * CubicBezier.easeInOut.value(at: (u - 0.62) / 0.38)
    }
}
