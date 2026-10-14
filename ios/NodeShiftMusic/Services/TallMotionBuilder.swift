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
        let scale = max(canvas.width / extent.width, canvas.height / extent.height)
        let width = extent.width * scale
        let height = extent.height * scale
        return origin
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: (canvas.width - width) / 2, y: (canvas.height - height) / 2))
            .cropped(to: rect)
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
