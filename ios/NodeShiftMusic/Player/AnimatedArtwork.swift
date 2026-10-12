import AVFoundation
import MediaPlayer
import UIKit

@available(iOS 26.0, *)
enum AnimatedArtwork {
    private static var cache: [String: MPMediaItemAnimatedArtwork] = [:]

    static func apply(to info: inout [String: Any], track: TrackRecord) {
        guard let name = track.motionName else { return }
        let videoURL = AppPaths.motionURL(name)
        guard FileManager.default.fileExists(atPath: videoURL.path) else { return }
        let key = MPNowPlayingInfoProperty1x1AnimatedArtwork
        guard MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys.contains(key) else { return }
        if let cached = cache[name] {
            info[key] = cached
            return
        }
        let coverURL = track.coverName.map { AppPaths.coverURL($0) }
        let artwork = MPMediaItemAnimatedArtwork(
            artworkID: name,
            previewImageRequestHandler: { _ in
                if let coverURL, let image = CoverImageLoader.downsample(coverURL, maxPixel: 1000) {
                    return image
                }
                return await previewFrame(of: videoURL)
            },
            videoAssetFileURLRequestHandler: { _ in
                videoURL
            }
        )
        cache[name] = artwork
        info[key] = artwork
    }

    private static func previewFrame(of url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1000, height: 1000)
        guard let result = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: result.image)
    }
}
