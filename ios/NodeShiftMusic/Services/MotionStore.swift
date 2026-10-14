import AVFoundation
import Foundation
import UIKit

actor MotionStore {
    static let shared = MotionStore()

    private var downloads: [String: Task<URL?, Never>] = [:]
    private var builds: [String: Task<URL?, Never>] = [:]

    nonisolated static func isRemote(_ name: String) -> Bool {
        name.hasPrefix(CoverSource.remotePrefix)
    }

    nonisolated static func hasAny(_ track: TrackRecord) -> Bool {
        track.motionName != nil || track.motion3x4Name != nil
    }

    nonisolated static func localURL(_ name: String) -> URL? {
        let url: URL
        if name.hasPrefix("cache:") {
            url = AppPaths.motionCacheDir.appendingPathComponent(String(name.dropFirst(6)))
        } else {
            url = AppPaths.motionURL(name)
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    nonisolated static func hasLocalFile(_ name: String) -> Bool {
        if isRemote(name) {
            return true
        }
        return localURL(name) != nil
    }

    func squareURL(_ name: String) async -> URL? {
        guard Self.isRemote(name) else {
            return Self.localURL(name)
        }
        let file = String(name.dropFirst(CoverSource.remotePrefix.count))
        guard !file.isEmpty, !file.contains("/") else { return nil }
        let target = AppPaths.motionCacheDir.appendingPathComponent(file)
        if Self.isUsable(target) {
            return target
        }
        if let running = downloads[file] {
            return await running.value
        }
        let remote = SiteAPI.shared.motionURL(file)
        let task = Task<URL?, Never> {
            do {
                try await Net.download(remote, to: target)
                guard MotionStore.isUsable(target) else {
                    try? FileManager.default.removeItem(at: target)
                    return nil
                }
                return target
            } catch {
                return nil
            }
        }
        downloads[file] = task
        let result = await task.value
        downloads[file] = nil
        return result
    }

    func tallURL(squareName: String?, tallName: String?) async -> URL? {
        if let tallName, !Self.isRemote(tallName), let local = Self.localURL(tallName) {
            return local
        }
        guard let squareName, let square = await squareURL(squareName) else { return nil }
        let stem = square.deletingPathExtension().lastPathComponent
        let target = AppPaths.motionCacheDir.appendingPathComponent("\(stem)-tall.mp4")
        if Self.isUsable(target) {
            return target
        }
        if let running = builds[stem] {
            return await running.value
        }
        let task = Task<URL?, Never> {
            do {
                try await TallMotionBuilder.build(from: square, to: target)
                return MotionStore.isUsable(target) ? target : nil
            } catch {
                return nil
            }
        }
        builds[stem] = task
        let result = await task.value
        builds[stem] = nil
        return result
    }

    func firstFrame(of url: URL, maxPixel: CGFloat = 1000) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        guard let result = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: result.image)
    }

    nonisolated static func isUsable(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else { return false }
        return size > 20_000
    }

    func trimCache(limit: Int64 = 500 * 1024 * 1024) {
        let directory = AppPaths.motionCacheDir
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var entries: [(url: URL, size: Int64, date: Date)] = files.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey])
            return (url, Int64(values?.fileSize ?? 0), values?.contentAccessDate ?? .distantPast)
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > limit else { return }
        entries.sort { $0.date < $1.date }
        for entry in entries where total > limit {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
