import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum TallMotionError: Error {
    case noVideoTrack
    case exportUnavailable
    case exportFailed(String)
}

enum TallMotionBuilder {
    static let canvas = CGSize(width: 810, height: 1080)

    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func compose(_ source: CIImage, canvas: CGSize = TallMotionBuilder.canvas) -> CIImage {
        let rect = CGRect(origin: .zero, size: canvas)
        let extent = source.extent
        guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else {
            return CIImage(color: CIColor(red: 0.04, green: 0.04, blue: 0.04)).cropped(to: rect)
        }
        let origin = source.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))

        let fitScale = canvas.width / extent.width
        let fitHeight = extent.height * fitScale
        let foreground = origin
            .transformed(by: CGAffineTransform(scaleX: fitScale, y: fitScale))
            .transformed(by: CGAffineTransform(translationX: 0, y: canvas.height - fitHeight))
        if fitHeight >= canvas.height {
            return foreground.cropped(to: rect)
        }

        let quarter = CGSize(width: canvas.width / 4, height: canvas.height / 4)
        let fillScale = max(quarter.width / extent.width, quarter.height / extent.height)
        let fillWidth = extent.width * fillScale
        let fillHeight = extent.height * fillScale
        let smallRect = CGRect(origin: .zero, size: quarter)
        let backdrop = origin
            .transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale))
            .transformed(by: CGAffineTransform(translationX: (quarter.width - fillWidth) / 2, y: (quarter.height - fillHeight) / 2))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 7)
            .cropped(to: smallRect)
            .transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let shade = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.3)).cropped(to: rect)
        let base = shade.composited(over: backdrop).cropped(to: rect)

        let fade = min(canvas.height * 0.1, fitHeight * 0.4)
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: 0, y: canvas.height - fitHeight + fade)
        gradient.point1 = CGPoint(x: 0, y: canvas.height - fitHeight)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        let mask = (gradient.outputImage ?? CIImage(color: CIColor.white)).cropped(to: rect)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = foreground
        blend.backgroundImage = base
        blend.maskImage = mask
        return (blend.outputImage ?? foreground.composited(over: base)).cropped(to: rect)
    }

    static func tallPreview(from image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let output = compose(input)
        guard let cgImage = context.createCGImage(output, from: CGRect(origin: .zero, size: canvas)) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func build(from source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw TallMotionError.noVideoTrack }
        let nominal = try await track.load(.nominalFrameRate)
        let rate = Int32(max(15, min(60, nominal.rounded())))

        let composition = AVMutableVideoComposition(asset: asset) { request in
            let output = TallMotionBuilder.compose(request.sourceImage)
            request.finish(with: output, context: nil)
        }
        composition.renderSize = canvas
        composition.frameDuration = CMTime(value: 1, timescale: rate)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw TallMotionError.exportUnavailable
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp4")
        try? FileManager.default.removeItem(at: temporary)
        session.outputURL = temporary
        session.outputFileType = .mp4
        session.videoComposition = composition
        session.shouldOptimizeForNetworkUse = false

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: temporary)
            throw TallMotionError.exportFailed(session.error?.localizedDescription ?? "export")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
