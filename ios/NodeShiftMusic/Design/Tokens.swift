import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Palette {
    static let bg = Color(hex: 0x0A0A0A)
    static let surface = Color.white.opacity(0.05)
    static let surface2 = Color.white.opacity(0.09)
    static let line = Color.white.opacity(0.08)
    static let line2 = Color.white.opacity(0.14)
    static let text = Color(hex: 0xE5E5E5)
    static let white = Color.white
    static let muted = Color.white.opacity(0.60)
    static let dim = Color.white.opacity(0.45)
    static let danger = Color(hex: 0xFF5555)
    static let ok = Color(hex: 0x3FB950)
    static let warn = Color(hex: 0xE3B341)
    static let playerBar = Color(hex: 0x0E0E0E, opacity: 0.82)
    static let sheet = Color(hex: 0x121212, opacity: 0.96)
    static let modal = Color(hex: 0x121212)
    static let queue = Color(hex: 0x101010)
    static let toast = Color(hex: 0x161616, opacity: 0.95)
    static let pill = Color(hex: 0x141414, opacity: 0.90)
}

enum Radius {
    static let sm: CGFloat = 10
    static let tile: CGFloat = 12
    static let nav: CGFloat = 14
    static let card: CGFloat = 20
    static let pill: CGFloat = 999
}

enum Face: String {
    case interRegular = "Inter-Regular"
    case interMedium = "Inter-Medium"
    case interSemibold = "Inter-SemiBold"
    case unboundedMedium = "Unbounded-Medium"
    case unboundedSemibold = "Unbounded-SemiBold"
    case monoRegular = "JetBrainsMono-Regular"
    case monoMedium = "JetBrainsMono-Medium"
    case monoSemibold = "JetBrainsMono-SemiBold"
}

extension Font {
    static func nsm(_ face: Face, _ size: CGFloat) -> Font {
        .custom(face.rawValue, size: size)
    }
}

struct Scale {
    var factor: CGFloat = 1

    func callAsFunction(_ value: CGFloat) -> CGFloat {
        value * factor
    }

    static func forWidth(_ width: CGFloat) -> Scale {
        Scale(factor: min(max(width / 390, 0.84), 1.3))
    }
}

private struct ScaleKey: EnvironmentKey {
    static let defaultValue = Scale()
}

extension EnvironmentValues {
    var s: Scale {
        get { self[ScaleKey.self] }
        set { self[ScaleKey.self] = newValue }
    }
}

enum Motion {
    static func expoOut(_ duration: Double) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: duration)
    }

    static let layout = Animation.timingCurve(0.4, 0, 0.1, 1, duration: 0.45)
    static let opacity = Animation.timingCurve(0.25, 0.1, 0.35, 1, duration: 0.3)
    static let spring = Animation.spring(response: 0.281, dampingFraction: 0.56)
    static let coverSpring = Animation.spring(response: 0.424, dampingFraction: 0.742)
    static let page = Animation.easeOut(duration: 0.28)
}
