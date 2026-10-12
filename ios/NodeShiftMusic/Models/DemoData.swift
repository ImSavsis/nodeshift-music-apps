import SwiftUI
import UIKit

enum DemoData {
    struct Album {
        let name: String
        let artist: String
        let hueA: CGFloat
        let hueB: CGFloat
        let cover: String
    }

    static let albums: [Album] = [
        Album(name: "Static Bloom", artist: "Aurora Vale", hueA: 0.58, hueB: 0.82, cover: "demo-a.jpg"),
        Album(name: "Harbour Lights", artist: "Kite Runner", hueA: 0.05, hueB: 0.62, cover: "demo-b.jpg"),
        Album(name: "Тишина после", artist: "Низкая орбита", hueA: 0.72, hueB: 0.50, cover: "demo-c.jpg"),
        Album(name: "Glass Season", artist: "Lumen Hall", hueA: 0.13, hueB: 0.95, cover: "demo-d.jpg"),
        Album(name: "Quiet Engines", artist: "North Sea Radio", hueA: 0.38, hueB: 0.60, cover: "demo-e.jpg"),
        Album(name: "Лето в записи", artist: "Мята", hueA: 0.30, hueB: 0.12, cover: "demo-f.jpg"),
    ]

    private static let rows: [(String, Int, String, Int)] = [
        ("Neon Rivers", 0, "flac", 214),
        ("Paper Boats", 1, "mp3", 242),
        ("Полночный город", 2, "flac", 228),
        ("Glass Season", 3, "flac", 312),
        ("Slow Static", 0, "flac", 177),
        ("Ferris Wheel", 1, "mp3", 201),
        ("Холодный свет", 2, "flac", 255),
        ("Afterglow", 3, "flac", 189),
        ("Quiet Engines", 4, "mp3", 361),
        ("Тёплый шум", 5, "mp3", 164),
        ("Lowlight", 4, "flac", 235),
        ("Sundial", 0, "flac", 210),
        ("Берег", 5, "flac", 198),
        ("Nightbus", 1, "mp3", 284),
    ]

    static func ensureCovers() {
        for album in albums {
            let url = AppPaths.coverURL(album.cover)
            if FileManager.default.fileExists(atPath: url.path) {
                continue
            }
            let size = CGSize(width: 640, height: 640)
            let image = UIGraphicsImageRenderer(size: size).image { renderer in
                let context = renderer.cgContext
                let colors = [
                    UIColor(hue: album.hueA, saturation: 0.55, brightness: 0.62, alpha: 1).cgColor,
                    UIColor(hue: album.hueB, saturation: 0.62, brightness: 0.22, alpha: 1).cgColor,
                ]
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                }
                context.setFillColor(UIColor(white: 1, alpha: 0.10).cgColor)
                context.fillEllipse(in: CGRect(x: size.width * 0.18, y: size.height * 0.12, width: size.width * 0.64, height: size.width * 0.64))
                context.setFillColor(UIColor(white: 0, alpha: 0.18).cgColor)
                context.fillEllipse(in: CGRect(x: size.width * 0.42, y: size.height * 0.46, width: size.width * 0.5, height: size.width * 0.5))
                context.setStrokeColor(UIColor(white: 1, alpha: 0.22).cgColor)
                context.setLineWidth(3)
                context.strokeEllipse(in: CGRect(x: size.width * 0.3, y: size.height * 0.3, width: size.width * 0.4, height: size.width * 0.4))
            }
            if let data = image.jpegData(compressionQuality: 0.85) {
                try? data.write(to: url)
            }
        }
    }

    static func tracks() -> [TrackRecord] {
        ensureCovers()
        let now = Date()
        return rows.enumerated().map { index, row in
            let album = albums[row.1]
            var track = TrackRecord.blank(id: "demo-\(index)")
            track.title = row.0
            track.artist = album.artist
            track.album = album.name
            track.trackNumber = index % 5 + 1
            track.durationMs = row.3 * 1000
            track.format = row.2
            track.bitrateKbps = row.2 == "mp3" ? 320 : nil
            track.fileName = "demo-\(index).\(row.2)"
            track.fileSize = Int64(row.3) * (row.2 == "mp3" ? 40_000 : 110_000)
            track.coverName = album.cover
            track.isFavorite = index % 3 == 0
            track.playCount = (index * 7) % 23
            track.lastPlayedAt = index < 6 ? now.addingTimeInterval(-Double(index) * 3600) : nil
            track.addedAt = now.addingTimeInterval(-Double(index) * 86_400)
            return track
        }
    }

    static let lrc = """
    [00:04.00]Neon rivers hum beneath the sleeping town
    [00:09.50]Every window holds a quiet constellation
    [00:15.00]We keep walking where the streetlights bend
    [00:20.50]Counting echoes that the night forgot to end
    [00:27.00]Hold the silence like a fragile coin
    [00:32.00]Spin it in the palm of a tired sky
    [00:37.50]Nothing here is ever really lost
    [00:43.00]Only waiting for the morning to arrive
    [00:50.00]Hold the silence like a fragile coin
    [00:55.00]Spin it in the palm of a tired sky
    [01:00.50]Nothing here is ever really lost
    [01:06.00]Only waiting for the morning to arrive
    [01:14.00]Я иду по пустым улицам, где гаснут фонари
    [01:20.00]Город засыпает, а утро ещё далеко
    [01:27.00]Слышишь, как тихо дышит ночная река
    [01:34.00]Мы останемся здесь до первого света
    """
}
