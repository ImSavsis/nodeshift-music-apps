import SwiftUI
import ImageIO
import NSMCore

final class CoverImageLoader: @unchecked Sendable {
    static let shared = CoverImageLoader()

    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 400
    }

    private func key(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(url.lastPathComponent)#\(maxPixel)" as NSString
    }

    func cached(url: URL, maxPixel: Int) -> UIImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    func image(url: URL, maxPixel: Int) async -> UIImage? {
        if let hit = cached(url: url, maxPixel: maxPixel) {
            return hit
        }
        let loaded: UIImage? = await Task.detached(priority: .userInitiated) {
            CoverImageLoader.downsample(url, maxPixel: maxPixel)
        }.value
        if let loaded {
            cache.setObject(loaded, forKey: key(url, maxPixel))
        }
        return loaded
    }

    static func downsample(_ url: URL, maxPixel: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

struct CoverArt: View {
    let coverName: String?
    var radius: CGFloat = Radius.tile
    var live = true
    var maxPixel = 480

    @Environment(\.s) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var drifting: Bool {
        live && !reduceMotion && !lowPower && image != nil
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    ZStack {
                        if let image {
                            artwork(image, size: proxy.size)
                        } else {
                            fallback
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: s(radius), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: s(radius), style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
            .task(id: coverName) {
                await load()
            }
    }

    private var fallback: some View {
        ZStack {
            Palette.surface
            CrystalMark(size: s(28), dim: true)
        }
    }

    @ViewBuilder
    private func artwork(_ image: UIImage, size: CGSize) -> some View {
        if drifting {
            let drift = CoverMotion.drift(seed: coverName ?? "")
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let progress = CoverMotion.driftProgress(time: time, drift: drift)
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(
                            CoverMotion.driftScale(progress: progress),
                            anchor: UnitPoint(x: drift.originX / 100, y: drift.originY / 100)
                        )
                        .offset(
                            x: size.width * drift.shiftX / 100 * progress,
                            y: size.height * drift.shiftY / 100 * progress
                        )
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.clear, location: 0.38),
                                    .init(color: Color.white.opacity(0.18), location: 0.5),
                                    .init(color: Color.clear, location: 0.62),
                                ],
                                startPoint: UnitPoint(x: -0.102, y: 0.219),
                                endPoint: UnitPoint(x: 1.102, y: 0.781)
                            )
                        )
                        .frame(width: size.width, height: size.height)
                        .offset(x: size.width * CoverMotion.sheenOffset(time: time, drift: drift))
                        .blendMode(.softLight)
                        .allowsHitTesting(false)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        } else {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }

    private func load() async {
        guard let name = coverName else {
            image = nil
            return
        }
        let url = AppPaths.coverURL(name)
        if let hit = CoverImageLoader.shared.cached(url: url, maxPixel: maxPixel) {
            image = hit
            return
        }
        image = await CoverImageLoader.shared.image(url: url, maxPixel: maxPixel)
    }
}
