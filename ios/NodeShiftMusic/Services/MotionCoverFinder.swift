import Foundation
import NSMCore

private struct AppleAlbumResponse: Decodable {
    let results: [AppleAlbum]
}

private struct AppleAlbum: Decodable {
    let collectionId: Int?
    let collectionName: String?
    let artistName: String?
    let collectionViewUrl: String?
}

struct MotionFiles: Sendable {
    var square: URL?
    var tall: URL?
}

enum MotionCoverFinder {
    static func find(artist: String, album: String, into directory: URL, key: String) async -> MotionFiles? {
        guard !album.isEmpty else { return nil }
        let pages = await candidatePages(artist: artist, album: album)
        for page in pages.prefix(6) {
            if let found = await motionURLs(page: page) {
                let square = found.square
                let tall = found.tall
                var files = MotionFiles()
                if let square, let local = await fetchBest(master: square, to: directory.appendingPathComponent("\(key).mp4")) {
                    files.square = local
                }
                if let tall, let local = await fetchBest(master: tall, to: directory.appendingPathComponent("\(key)-tall.mp4")) {
                    files.tall = local
                }
                if files.square != nil || files.tall != nil {
                    return files
                }
            }
        }
        return nil
    }

    private static func candidatePages(artist: String, album: String) async -> [URL] {
        var pages: [URL] = []
        for country in ["us", "ru"] {
            await RateLimiter.shared.wait("itunes", interval: 3.2)
            guard let url = Net.components("https://itunes.apple.com/search", [
                "term": "\(artist) \(album)",
                "media": "music",
                "entity": "album",
                "limit": "12",
                "country": country,
            ]) else { continue }
            guard let response = try? await Net.json(url, as: AppleAlbumResponse.self) else { continue }
            for item in response.results {
                guard let name = item.collectionName, let singer = item.artistName,
                      let link = item.collectionViewUrl, let page = URL(string: link) else { continue }
                if TextMatching.titleRatio(album, name) >= 0.8, TextMatching.artistRatio(artist, singer) >= 0.7 {
                    pages.append(page)
                }
            }
            if !pages.isEmpty {
                break
            }
        }
        return pages
    }

    static func collectVideos(_ node: Any, into found: inout [String: String]) {
        if let dictionary = node as? [String: Any] {
            for (key, value) in dictionary {
                if (key == "motionDetailSquare" || key == "motionSquareVideo1x1"), let inner = value as? [String: Any],
                   let video = inner["video"] as? String, found["square"] == nil {
                    found["square"] = video
                } else if (key == "motionDetailTall" || key == "motionTallVideo3x4"), let inner = value as? [String: Any],
                          let video = inner["video"] as? String, found["tall"] == nil {
                    found["tall"] = video
                } else {
                    collectVideos(value, into: &found)
                }
            }
        } else if let array = node as? [Any] {
            for item in array {
                collectVideos(item, into: &found)
            }
        }
    }

    private static func motionURLs(page: URL) async -> (square: URL?, tall: URL?)? {
        await RateLimiter.shared.wait("applepage", interval: 1.5)
        guard let data = try? await Net.data(page, agent: Net.browserAgent),
              let html = String(data: data, encoding: .utf8) else { return nil }
        guard let open = html.range(of: "id=\"serialized-server-data\""),
              let start = html[open.upperBound...].firstIndex(of: ">"),
              let end = html.range(of: "</script>", range: start..<html.endIndex) else { return nil }
        let jsonText = String(html[html.index(after: start)..<end.lowerBound])
        guard let jsonData = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) else { return nil }
        var found: [String: String] = [:]
        collectVideos(object, into: &found)
        let square = found["square"].flatMap { URL(string: $0) }
        let tall = found["tall"].flatMap { URL(string: $0) }
        if square == nil && tall == nil {
            return nil
        }
        return (square, tall)
    }

    struct Variant {
        var url: URL
        var width: Int
        var bandwidth: Int
    }

    static func parseVariants(master: String, base: URL) -> [Variant] {
        var variants: [Variant] = []
        let lines = master.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("#EXT-X-STREAM-INF:"), line.contains("avc1"), index + 1 < lines.count {
                let uri = lines[index + 1].trimmingCharacters(in: .whitespaces)
                var width = 0
                if let range = line.range(of: "RESOLUTION=") {
                    let rest = line[range.upperBound...]
                    let digits = rest.prefix { $0.isNumber }
                    width = Int(digits) ?? 0
                }
                var bandwidth = 0
                if let range = line.range(of: ",BANDWIDTH=") ?? line.range(of: ":BANDWIDTH=") {
                    let digits = line[range.upperBound...].prefix { $0.isNumber }
                    bandwidth = Int(digits) ?? 0
                }
                if let url = URL(string: uri, relativeTo: base)?.absoluteURL, width > 0 {
                    variants.append(Variant(url: url, width: width, bandwidth: bandwidth))
                }
                index += 2
                continue
            }
            index += 1
        }
        return variants
    }

    static func pickVariant(_ variants: [Variant]) -> Variant? {
        let usable = variants.filter { $0.width >= 480 && $0.width <= 1100 }
        let pool = usable.isEmpty ? variants : usable
        return pool.min { left, right in
            let l = abs(left.width - 960)
            let r = abs(right.width - 960)
            if l != r {
                return l < r
            }
            return left.bandwidth < right.bandwidth
        }
    }

    static func mapURI(variantPlaylist: String, base: URL) -> URL? {
        for line in variantPlaylist.components(separatedBy: .newlines) where line.hasPrefix("#EXT-X-MAP:") {
            guard let range = line.range(of: "URI=\"") else { continue }
            let rest = line[range.upperBound...]
            guard let close = rest.firstIndex(of: "\"") else { continue }
            return URL(string: String(rest[..<close]), relativeTo: base)?.absoluteURL
        }
        for line in variantPlaylist.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                return URL(string: trimmed, relativeTo: base)?.absoluteURL
            }
        }
        return nil
    }

    private static func fetchBest(master: URL, to destination: URL) async -> URL? {
        guard let masterData = try? await Net.data(master, agent: Net.browserAgent),
              let masterText = String(data: masterData, encoding: .utf8),
              let variant = pickVariant(parseVariants(master: masterText, base: master)),
              let variantData = try? await Net.data(variant.url, agent: Net.browserAgent),
              let variantText = String(data: variantData, encoding: .utf8),
              let fileURL = mapURI(variantPlaylist: variantText, base: variant.url) else { return nil }
        guard (try? await Net.download(fileURL, to: destination, agent: Net.browserAgent)) != nil else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: destination) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 12)) ?? Data()
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
        guard head.count >= 8, head.subdata(in: 4..<8) == Data("ftyp".utf8), size > 100_000 else {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        return destination
    }
}
