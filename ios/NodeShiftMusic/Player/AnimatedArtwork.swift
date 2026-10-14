import AVFoundation
import MediaPlayer
import UIKit

@available(iOS 26.0, *)
enum AnimatedArtwork {
    private static let lock = NSLock()
    private static var cache: [String: MPMediaItemAnimatedArtwork] = [:]

    static func apply(to info: inout [String: Any], track: TrackRecord) {
        guard MotionStore.hasAny(track) else { return }
        let supported = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
        let squareKey = MPNowPlayingInfoProperty1x1AnimatedArtwork
        let tallKey = MPNowPlayingInfoProperty3x4AnimatedArtwork
        if supported.contains(squareKey), let square = track.motionName {
            info[squareKey] = artwork(
                id: "\(square)#1x1",
                coverName: track.coverName,
                squareName: square,
                tallName: nil,
                tall: false
            )
        }
        if supported.contains(tallKey), let source = track.motion3x4Name ?? track.motionName {
            info[tallKey] = artwork(
                id: "\(source)#3x4",
                coverName: track.coverName,
                squareName: track.motionName,
                tallName: track.motion3x4Name,
                tall: true
            )
        }
    }

    private static func artwork(
        id: String,
        coverName: String?,
        squareName: String?,
        tallName: String?,
        tall: Bool
    ) -> MPMediaItemAnimatedArtwork {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[id] {
            return hit
        }
        let created = MPMediaItemAnimatedArtwork(
            artworkID: id,
            previewImageRequestHandler: { _ in
                await preview(coverName: coverName, squareName: squareName, tall: tall)
            },
            videoAssetFileURLRequestHandler: { _ in
                if tall {
                    return await MotionStore.shared.tallURL(squareName: squareName, tallName: tallName)
                }
                guard let squareName else { return nil }
                return await MotionStore.shared.squareURL(squareName)
            }
        )
        if cache.count > 12 {
            cache.removeAll()
        }
        cache[id] = created
        return created
    }

    private static func preview(coverName: String?, squareName: String?, tall: Bool) async -> UIImage? {
        var base: UIImage?
        if let coverName {
            base = await CoverImageLoader.shared.image(url: CoverSource.url(for: coverName, maxPixel: 1000), maxPixel: 1000)
        }
        if base == nil, let squareName, let video = await MotionStore.shared.squareURL(squareName) {
            base = await MotionStore.shared.firstFrame(of: video)
        }
        guard let base else { return nil }
        return tall ? TallMotionBuilder.tallPreview(from: base) : squared(base)
    }

    private static func squared(_ image: UIImage) -> UIImage {
        guard let source = image.cgImage, abs(source.width - source.height) > 1 else { return image }
        let side = min(source.width, source.height)
        let rect = CGRect(x: (source.width - side) / 2, y: (source.height - side) / 2, width: side, height: side)
        guard let cropped = source.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
    }
}
