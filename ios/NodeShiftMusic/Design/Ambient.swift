import SwiftUI
import ImageIO
import NSMCore

final class PaletteProvider: @unchecked Sendable {
    static let shared = PaletteProvider()

    private var cache: [String: [RGB8]] = [:]
    private let lock = NSLock()

    func cached(_ key: String) -> [RGB8]? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    func palette(coverName: String?) async -> [RGB8] {
        guard let name = coverName else {
            return PaletteExtractor.fallback
        }
        if let hit = cached(name) {
            return hit
        }
        let url = CoverSource.url(for: name, maxPixel: 300)
        let computed: [RGB8]
        if url.isFileURL {
            computed = await Task.detached(priority: .utility) {
                guard let pixels = PaletteProvider.pixels(url: url) else {
                    return PaletteExtractor.fallback
                }
                return PaletteExtractor.extract(rgba: pixels)
            }.value
        } else {
            let fetched = try? await URLSession.shared.data(from: url)
            let payload = fetched?.0
            computed = await Task.detached(priority: .utility) {
                guard let payload, let pixels = PaletteProvider.pixels(data: payload) else {
                    return PaletteExtractor.fallback
                }
                return PaletteExtractor.extract(rgba: pixels)
            }.value
        }
        lock.lock()
        cache[name] = computed
        lock.unlock()
        return computed
    }

    static func pixels(url: URL) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return pixels(source: source)
    }

    static func pixels(data: Data) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pixels(source: source)
    }

    private static func pixels(source: CGImageSource) -> [UInt8]? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let size = 48
        var data = [UInt8](repeating: 0, count: size * size * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        return drawn ? data : nil
    }
}

enum NoiseTile {
    static let image: UIImage = {
        let size = 220
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for index in 0..<(size * size) {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let value = UInt8((seed >> 33) & 0xFF)
            pixels[index * 4] = value
            pixels[index * 4 + 1] = value
            pixels[index * 4 + 2] = value
            pixels[index * 4 + 3] = value
        }
        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let cgImage = CGImage(
                width: size,
                height: size,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            return UIImage()
        }
        return UIImage(cgImage: cgImage)
    }()
}

final class AmbientEngine {
    private var lastTime: Double?
    private var rate = 0.5
    private(set) var clocks: [Double] = [0, 0, 0]

    func advance(now: Double, playing: Bool, bpm: Double) {
        let dt = min(0.1, max(0, now - (lastTime ?? now)))
        lastTime = now
        let target = AmbientMotion.rate(forBpm: bpm, playing: playing)
        rate += (target - rate) * (1 - pow(0.98, dt * 60))
        for index in clocks.indices {
            clocks[index] += dt * rate * AmbientMotion.blobs[index].speed
        }
    }

    func draw(in context: inout GraphicsContext, size: CGSize, palette: [RGB8]) {
        let vmax = max(size.width, size.height) / 100
        let diameter = 78 * vmax
        let centers: [CGPoint] = [
            CGPoint(x: -26 * vmax + diameter / 2, y: -30 * vmax + diameter / 2),
            CGPoint(x: size.width + 28 * vmax - diameter / 2, y: size.height + 34 * vmax - diameter / 2),
            CGPoint(x: size.width + 22 * vmax - diameter / 2, y: -34 * vmax + diameter / 2),
        ]
        for index in 0..<min(3, palette.count) {
            let frame = AmbientMotion.state(AmbientMotion.blobs[index], at: clocks[index])
            let center = CGPoint(
                x: centers[index].x + diameter * frame.x / 100,
                y: centers[index].y + diameter * frame.y / 100
            )
            let radius = diameter / 2 * frame.scale
            let reach = radius * 2.0.squareRoot() * 0.70
            let color = palette[index]
            let base = Color(.sRGB, red: Double(color.r) / 255, green: Double(color.g) / 255, blue: Double(color.b) / 255, opacity: 1)
            let gradient = Gradient(stops: [
                .init(color: base.opacity(0.5), location: 0),
                .init(color: base.opacity(0.18), location: 0.38 / 0.70),
                .init(color: base.opacity(0), location: 1),
            ])
            var layer = context
            layer.opacity = 0.72
            layer.fill(
                Path(ellipseIn: CGRect(x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2)),
                with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: reach)
            )
        }
    }
}

struct AmbientBackdrop: View {
    let palette: [RGB8]
    var playing: Bool
    var bpm: Double = AmbientMotion.defaultBpm

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = AmbientEngine()

    private var paletteKey: String {
        palette.map { "\($0.r),\($0.g),\($0.b)" }.joined(separator: "|")
    }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                Canvas { graphics, size in
                    if !reduceMotion {
                        engine.advance(now: context.date.timeIntervalSinceReferenceDate, playing: playing, bpm: bpm)
                    }
                    engine.draw(in: &graphics, size: size, palette: palette)
                }
            }
            .id(paletteKey)
            .transition(.opacity)
            LinearGradient(
                colors: [Palette.bg.opacity(0.2), Palette.bg.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(uiImage: NoiseTile.image)
                .resizable(resizingMode: .tile)
                .opacity(0.07)
                .blendMode(.softLight)
        }
        .animation(.easeInOut(duration: 1.6), value: paletteKey)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
