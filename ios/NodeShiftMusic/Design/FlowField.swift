import SwiftUI

final class FlowSimulation {
    struct Dot {
        var homeX: CGFloat
        var homeY: CGFloat
        var x: CGFloat
        var y: CGFloat
        var phase: CGFloat
        var ease: CGFloat
        var depth: CGFloat
    }

    private(set) var dots: [Dot] = []
    private var builtSize: CGSize = .zero
    private var builtScale: CGFloat = 0
    private var lastTime: Double?
    private(set) var clock: Double = 0

    static func randomFrom(_ n: Double) -> CGFloat {
        let s = sin(12.9898 * n + 4.1414) * 43758.5453
        return CGFloat(s - s.rounded(.down))
    }

    func rebuild(size: CGSize, scale: CGFloat) {
        if size == builtSize && scale == builtScale {
            return
        }
        builtSize = size
        builtScale = scale
        let width = size.width
        let height = size.height
        let step = (width < 640 ? 40 : 48) * scale
        let margin = (width < 640 ? 16 : 40) * scale
        let usable = min(width - 2 * margin, 1152 * scale)
        let cols = max(2, Int((usable / step).rounded(.down)) + 1)
        let rows = Int((height / step).rounded(.up)) + 1
        let startX = (width - CGFloat(cols - 1) * step) / 2
        let startY = (height - CGFloat(rows - 1) * step) / 2
        var built: [Dot] = []
        built.reserveCapacity(cols * rows)
        var n = 0.0
        for row in 0..<rows {
            for col in 0..<cols {
                let rnd = Self.randomFrom(n)
                let x = startX + CGFloat(col) * step
                let y = startY + CGFloat(row) * step
                built.append(Dot(
                    homeX: x,
                    homeY: y,
                    x: x,
                    y: y,
                    phase: rnd * .pi * 2,
                    ease: 0.06 + 0.05 * rnd,
                    depth: rnd
                ))
                n += 1
            }
        }
        dots = built
    }

    func advance(to now: Double) {
        let dt = min(0.05, max(0, now - (lastTime ?? now)))
        lastTime = now
        clock += dt
    }

    func draw(in context: inout GraphicsContext, size: CGSize, progress: Double, animate: Bool) {
        let width = size.width
        let height = size.height
        let midX = width / 2
        let wave = 1 - progress
        let strength = min(1, 2 * sin(progress * .pi))
        let time = animate ? clock : 0
        let centerX = width * 0.5
        let centerY = height * 0.45
        for index in dots.indices {
            var dot = dots[index]
            let offset = (Double(dot.homeY / height) - wave) / 0.15
            let m = CGFloat(strength * exp(-offset * offset))
            let pull = 1 - 0.26 * m
            let calm = 1 - 0.5 * m
            let wobbleX = dot.homeX + 6 * CGFloat(sin(0.6 * time + Double(dot.phase))) * calm
            let wobbleY = dot.homeY + 6 * CGFloat(cos(0.5 * time + 1.3 * Double(dot.phase))) * calm
            let targetX = midX + (wobbleX - midX) * pull
            if animate {
                dot.x += (targetX - dot.x) * dot.ease
                dot.y += (wobbleY - dot.y) * dot.ease
            } else {
                dot.x = targetX
                dot.y = wobbleY
            }
            dots[index] = dot
            var alpha = 0.06 * (0.55 + 0.9 * Double(dot.depth)) * (1 + 1.6 * Double(m))
            let dx = Double(dot.x - centerX) / Double(width * 0.78)
            let dy = Double(dot.y - centerY) / Double(height * 0.68)
            let distance = (dx * dx + dy * dy).squareRoot()
            let mask = distance <= 0.38 ? 1.0 : max(0, 1 - (distance - 0.38) / 0.54)
            alpha *= mask
            if alpha <= 0.002 {
                continue
            }
            let tint = (229 + Double(Int(26 * 0.4 * Double(m)))) / 255
            let radius = 2.4 * (0.7 + 0.6 * dot.depth) * (1 + 0.3 * m) * 0.5
            let rect = CGRect(x: dot.x - radius, y: dot.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Color(.sRGB, red: tint, green: tint, blue: tint, opacity: alpha)))
        }
    }
}

struct FlowFieldView: View {
    var progress: Double = 0
    @Environment(\.s) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var simulation = FlowSimulation()

    var body: some View {
        let animate = !reduceMotion && SoundSettings.shared.ambientMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animate)) { context in
            Canvas { graphics, size in
                simulation.rebuild(size: size, scale: s.factor)
                if animate {
                    simulation.advance(to: context.date.timeIntervalSinceReferenceDate)
                }
                simulation.draw(in: &graphics, size: size, progress: progress, animate: animate)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
