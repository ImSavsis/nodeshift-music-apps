import SwiftUI

struct CrystalMark: View {
    var size: CGFloat = 96
    var dim = false

    private static let gradientA = Gradient(stops: [
        .init(color: Color.white.opacity(0.95), location: 0),
        .init(color: Color(hex: 0xBFC4D0, opacity: 0.55), location: 1),
    ])

    private static let gradientB = Gradient(stops: [
        .init(color: Color(hex: 0xE8EBF2, opacity: 0.8), location: 0),
        .init(color: Color(hex: 0x8A90A0, opacity: 0.4), location: 1),
    ])

    var body: some View {
        Canvas { context, canvasSize in
            let k = min(canvasSize.width, canvasSize.height) / 96
            func path(_ points: [(CGFloat, CGFloat)], closed: Bool) -> Path {
                var p = Path()
                for (index, point) in points.enumerated() {
                    let mapped = CGPoint(x: point.0 * k, y: point.1 * k)
                    if index == 0 {
                        p.move(to: mapped)
                    } else {
                        p.addLine(to: mapped)
                    }
                }
                if closed {
                    p.closeSubpath()
                }
                return p
            }
            func fill(_ p: Path, _ gradient: Gradient, reversed: Bool, opacity: Double) {
                let box = p.boundingRect
                let start = reversed
                    ? CGPoint(x: box.maxX, y: box.minY)
                    : CGPoint(x: box.minX, y: box.minY)
                let end = reversed
                    ? CGPoint(x: box.minX, y: box.maxY)
                    : CGPoint(x: box.maxX, y: box.maxY)
                var layer = context
                layer.opacity = opacity
                layer.fill(p, with: .linearGradient(gradient, startPoint: start, endPoint: end))
            }
            fill(path([(48, 6), (76, 34), (48, 52)], closed: true), Self.gradientA, reversed: false, opacity: 1)
            fill(path([(48, 6), (20, 34), (48, 52)], closed: true), Self.gradientB, reversed: true, opacity: 1)
            fill(path([(20, 34), (48, 52), (48, 90)], closed: true), Self.gradientA, reversed: false, opacity: 0.7)
            fill(path([(76, 34), (48, 52), (48, 90)], closed: true), Self.gradientB, reversed: true, opacity: 0.8)
            context.stroke(
                path([(48, 6), (76, 34), (48, 52), (20, 34)], closed: true),
                with: .color(Color.white.opacity(0.45)),
                lineWidth: 0.8 * k
            )
            context.stroke(
                path([(20, 34), (48, 90), (76, 34)], closed: false),
                with: .color(Color.white.opacity(0.25)),
                lineWidth: 0.8 * k
            )
        }
        .frame(width: size, height: size)
        .opacity(dim ? 0.55 : 1)
        .accessibilityHidden(true)
    }
}
