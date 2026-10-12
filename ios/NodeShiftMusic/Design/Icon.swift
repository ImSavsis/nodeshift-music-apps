import SwiftUI
import NSMCore

enum IconPathBuilder {
    static func path(from commands: [PathCommand]) -> Path {
        var path = Path()
        for command in commands {
            switch command {
            case let .move(x, y):
                path.move(to: CGPoint(x: x, y: y))
            case let .line(x, y):
                path.addLine(to: CGPoint(x: x, y: y))
            case let .cubic(x1, y1, x2, y2, x, y):
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: x1, y: y1),
                    control2: CGPoint(x: x2, y: y2)
                )
            case let .quad(cx, cy, x, y):
                path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }

    static func polygon(_ points: String, closed: Bool) -> Path {
        var path = Path()
        for (index, point) in SVGPath.parsePoints(points).enumerated() {
            let mapped = CGPoint(x: point.0, y: point.1)
            if index == 0 {
                path.move(to: mapped)
            } else {
                path.addLine(to: mapped)
            }
        }
        if closed {
            path.closeSubpath()
        }
        return path
    }

    static func path(for node: IconNode) -> Path {
        switch node {
        case let .path(d):
            return path(from: SVGPath.parse(d))
        case let .circle(cx, cy, r):
            return Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        case let .line(x1, y1, x2, y2):
            var line = Path()
            line.move(to: CGPoint(x: x1, y: y1))
            line.addLine(to: CGPoint(x: x2, y: y2))
            return line
        case let .polyline(points):
            return polygon(points, closed: false)
        case let .polygon(points):
            return polygon(points, closed: true)
        case let .rect(x, y, width, height, rx):
            let rect = CGRect(x: x, y: y, width: width, height: height)
            return rx > 0 ? Path(roundedRect: rect, cornerRadius: rx) : Path(rect)
        }
    }
}

final class IconCache: @unchecked Sendable {
    static let shared = IconCache()

    private var storage: [LucideName: [Path]] = [:]
    private let lock = NSLock()

    func paths(for name: LucideName) -> [Path] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[name] {
            return cached
        }
        let built = name.nodes.map { IconPathBuilder.path(for: $0) }
        storage[name] = built
        return built
    }
}

struct Icon: View {
    let name: LucideName
    var size: CGFloat = 18
    var stroke: CGFloat = 2
    var filled = false

    var body: some View {
        Canvas { context, canvasSize in
            let k = min(canvasSize.width, canvasSize.height) / 24
            let transform = CGAffineTransform(scaleX: k, y: k)
            let style = StrokeStyle(lineWidth: stroke * k, lineCap: .round, lineJoin: .round)
            for path in IconCache.shared.paths(for: name) {
                let scaled = path.applying(transform)
                if filled {
                    context.fill(scaled, with: .foreground)
                }
                context.stroke(scaled, with: .foreground, style: style)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
