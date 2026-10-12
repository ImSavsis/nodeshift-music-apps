import Foundation

public struct RGB8: Equatable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }
}

public enum PaletteExtractor {
    public static let fallback: [RGB8] = [RGB8(72, 76, 94), RGB8(46, 50, 64), RGB8(28, 30, 40)]

    private struct Bucket {
        var weight = 0.0
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var hue: Double
        var order: Int
    }

    static func rgbToHsv(_ red: Double, _ green: Double, _ blue: Double) -> (Double, Double, Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        var hue = 0.0
        if delta != 0 {
            if maxValue == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue *= 60
            if hue < 0 {
                hue += 360
            }
        }
        return (hue, maxValue == 0 ? 0 : delta / maxValue, maxValue / 255)
    }

    static func hsvToRgb(_ hue: Double, _ saturation: Double, _ value: Double) -> RGB8 {
        let chroma = value * saturation
        let wrapped = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let section = wrapped / 60
        let x = chroma * (1 - abs(section.truncatingRemainder(dividingBy: 2) - 1))
        let base = value - chroma
        let table: [(Double, Double, Double)] = [
            (chroma, x, 0),
            (x, chroma, 0),
            (0, chroma, x),
            (0, x, chroma),
            (x, 0, chroma),
            (chroma, 0, x),
        ]
        let pick = table[min(5, Int(section.rounded(.down)))]
        func byte(_ component: Double) -> Int {
            Int(((component + base) * 255 + 0.5).rounded(.down))
        }
        return RGB8(byte(pick.0), byte(pick.1), byte(pick.2))
    }

    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }

    static func tone(_ hue: Double, _ saturation: Double, _ value: Double) -> RGB8 {
        hsvToRgb(hue, saturation, value)
    }

    public static func extract(rgba: [UInt8]) -> [RGB8] {
        var buckets: [Int: Bucket] = [:]
        var grayTotal = 0.0
        var grayCount = 0.0
        var order = 0
        var index = 0
        while index + 3 < rgba.count {
            let red = Double(rgba[index])
            let green = Double(rgba[index + 1])
            let blue = Double(rgba[index + 2])
            index += 4
            let (hue, saturation, value) = rgbToHsv(red, green, blue)
            if value < 0.1 {
                continue
            }
            if saturation < 0.18 {
                grayTotal += (red + green + blue) / 3
                grayCount += 1
                continue
            }
            let key = Int((hue / 20).rounded(.down)) * 100
                + Int((saturation * 3).rounded(.down)) * 10
                + Int((value * 3).rounded(.down))
            let weight = saturation * (0.4 + value) + 0.05
            var bucket: Bucket
            if let existing = buckets[key] {
                bucket = existing
            } else {
                order += 1
                bucket = Bucket(hue: hue, order: order)
            }
            bucket.weight += weight
            bucket.red += red * weight
            bucket.green += green * weight
            bucket.blue += blue * weight
            bucket.hue = hue
            buckets[key] = bucket
        }

        let ranked = buckets.values.sorted { left, right in
            if left.weight != right.weight {
                return left.weight > right.weight
            }
            return left.order < right.order
        }

        guard let primary = ranked.first else {
            if grayCount == 0 {
                return fallback
            }
            let level = min(0.42, max(0.22, grayTotal / grayCount / 255 / 2.2))
            return [tone(230, 0.08, level), tone(230, 0.08, level * 0.62), tone(230, 0.06, level * 0.38)]
        }

        let (primaryHue, primarySaturation, _) = rgbToHsv(
            primary.red / primary.weight,
            primary.green / primary.weight,
            primary.blue / primary.weight
        )
        let mutedSaturation = min(0.38, max(0.16, primarySaturation * 0.55))
        let second = ranked.first { hueDistance($0.hue, primary.hue) >= 35 && $0.weight >= primary.weight * 0.45 }
        let secondHue = second?.hue ?? (primaryHue + 14)
        let secondSaturation = second != nil ? min(0.32, mutedSaturation * 0.9) : mutedSaturation * 0.7
        return [
            tone(primaryHue, mutedSaturation, 0.46),
            tone(secondHue, secondSaturation, second != nil ? 0.36 : 0.3),
            tone(primaryHue, min(0.24, mutedSaturation * 0.6), 0.2),
        ]
    }
}
