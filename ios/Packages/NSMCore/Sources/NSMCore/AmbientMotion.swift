import Foundation

public struct AmbientFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var scale: Double

    public init(x: Double, y: Double, scale: Double) {
        self.x = x
        self.y = y
        self.scale = scale
    }
}

public struct AmbientKeyframes: Equatable, Sendable {
    public let duration: Double
    public let start: AmbientFrame
    public let middle: AmbientFrame
    public let end: AmbientFrame
    public let speed: Double

    public init(duration: Double, start: AmbientFrame, middle: AmbientFrame, end: AmbientFrame, speed: Double) {
        self.duration = duration
        self.start = start
        self.middle = middle
        self.end = end
        self.speed = speed
    }
}

public enum AmbientMotion {
    public static let blobs: [AmbientKeyframes] = [
        AmbientKeyframes(
            duration: 46,
            start: AmbientFrame(x: -4, y: -2, scale: 1),
            middle: AmbientFrame(x: 16, y: 12, scale: 1.16),
            end: AmbientFrame(x: 4, y: 22, scale: 0.94),
            speed: 1
        ),
        AmbientKeyframes(
            duration: 58,
            start: AmbientFrame(x: 2, y: 4, scale: 1.05),
            middle: AmbientFrame(x: -18, y: -10, scale: 0.92),
            end: AmbientFrame(x: -6, y: -20, scale: 1.14),
            speed: 0.82
        ),
        AmbientKeyframes(
            duration: 52,
            start: AmbientFrame(x: 0, y: 0, scale: 0.96),
            middle: AmbientFrame(x: -14, y: 16, scale: 1.14),
            end: AmbientFrame(x: -22, y: 4, scale: 1),
            speed: 1.15
        ),
    ]

    public static let defaultBpm = 92.0
    public static let idleRate = 0.12

    public static func rate(forBpm bpm: Double, playing: Bool) -> Double {
        if !playing {
            return idleRate
        }
        let value = (bpm > 0 ? bpm : defaultBpm) / 100
        return min(1.6, max(0.6, value))
    }

    private static func mix(_ a: AmbientFrame, _ b: AmbientFrame, _ t: Double) -> AmbientFrame {
        AmbientFrame(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t,
            scale: a.scale + (b.scale - a.scale) * t
        )
    }

    public static func state(_ keyframes: AmbientKeyframes, at time: Double) -> AmbientFrame {
        let cycles = max(0, time) / keyframes.duration
        let iteration = Int(cycles.rounded(.down))
        var u = cycles - Double(iteration)
        if iteration % 2 == 1 {
            u = 1 - u
        }
        if u < 0.5 {
            return mix(keyframes.start, keyframes.middle, CubicBezier.easeInOut.value(at: u / 0.5))
        }
        return mix(keyframes.middle, keyframes.end, CubicBezier.easeInOut.value(at: (u - 0.5) / 0.5))
    }
}
