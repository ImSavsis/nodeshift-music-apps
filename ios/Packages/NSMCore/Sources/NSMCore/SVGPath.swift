import Foundation

public enum PathCommand: Equatable, Sendable {
    case move(Double, Double)
    case line(Double, Double)
    case cubic(Double, Double, Double, Double, Double, Double)
    case quad(Double, Double, Double, Double)
    case close
}

public enum SVGPath {
    private struct Scanner {
        let chars: [Character]
        var index = 0

        init(_ text: String) {
            chars = Array(text)
        }

        var atEnd: Bool {
            index >= chars.count
        }

        mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n" || chars[index] == "\t" || chars[index] == "\r" {
                index += 1
            }
        }

        mutating func peekCommand() -> Character? {
            skipSeparators()
            guard index < chars.count else { return nil }
            let c = chars[index]
            return c.isLetter ? c : nil
        }

        mutating func readCommand() -> Character? {
            guard let c = peekCommand() else { return nil }
            index += 1
            return c
        }

        mutating func readNumber() -> Double? {
            skipSeparators()
            guard index < chars.count else { return nil }
            var text = ""
            var i = index
            if chars[i] == "+" || chars[i] == "-" {
                text.append(chars[i])
                i += 1
            }
            var digits = 0
            while i < chars.count, chars[i].isASCII, chars[i].isNumber {
                text.append(chars[i])
                i += 1
                digits += 1
            }
            if i < chars.count, chars[i] == "." {
                text.append(".")
                i += 1
                while i < chars.count, chars[i].isASCII, chars[i].isNumber {
                    text.append(chars[i])
                    i += 1
                    digits += 1
                }
            }
            if digits == 0 {
                return nil
            }
            if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                var j = i + 1
                var exponent = "e"
                if j < chars.count, chars[j] == "+" || chars[j] == "-" {
                    exponent.append(chars[j])
                    j += 1
                }
                var expDigits = 0
                while j < chars.count, chars[j].isASCII, chars[j].isNumber {
                    exponent.append(chars[j])
                    j += 1
                    expDigits += 1
                }
                if expDigits > 0 {
                    text += exponent
                    i = j
                }
            }
            index = i
            return Double(text)
        }

        mutating func readFlag() -> Bool? {
            skipSeparators()
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c == "0" || c == "1" {
                index += 1
                return c == "1"
            }
            return nil
        }
    }

    public static func parse(_ d: String) -> [PathCommand] {
        var scanner = Scanner(d)
        var commands: [PathCommand] = []
        var cx = 0.0
        var cy = 0.0
        var startX = 0.0
        var startY = 0.0
        var lastControlX = 0.0
        var lastControlY = 0.0
        var previous: Character = " "
        var current: Character = " "

        while true {
            scanner.skipSeparators()
            if scanner.atEnd {
                break
            }
            var consumed = false
            if let command = scanner.readCommand() {
                current = command
                consumed = true
            } else if current == " " {
                break
            } else if current == "M" {
                current = "L"
            } else if current == "m" {
                current = "l"
            }
            let relative = current.isLowercase
            let upper = Character(current.uppercased())
            if upper == "Z" {
                if !consumed {
                    break
                }
                commands.append(.close)
                cx = startX
                cy = startY
                previous = upper
                continue
            }
            switch upper {
            case "M":
                guard let x = scanner.readNumber(), let y = scanner.readNumber() else { return commands }
                cx = relative ? cx + x : x
                cy = relative ? cy + y : y
                startX = cx
                startY = cy
                commands.append(.move(cx, cy))
            case "L":
                guard let x = scanner.readNumber(), let y = scanner.readNumber() else { return commands }
                cx = relative ? cx + x : x
                cy = relative ? cy + y : y
                commands.append(.line(cx, cy))
            case "H":
                guard let x = scanner.readNumber() else { return commands }
                cx = relative ? cx + x : x
                commands.append(.line(cx, cy))
            case "V":
                guard let y = scanner.readNumber() else { return commands }
                cy = relative ? cy + y : y
                commands.append(.line(cx, cy))
            case "C":
                guard let a = scanner.readNumber(), let b = scanner.readNumber(),
                      let c = scanner.readNumber(), let dd = scanner.readNumber(),
                      let x = scanner.readNumber(), let y = scanner.readNumber() else { return commands }
                let x1 = relative ? cx + a : a
                let y1 = relative ? cy + b : b
                let x2 = relative ? cx + c : c
                let y2 = relative ? cy + dd : dd
                let ex = relative ? cx + x : x
                let ey = relative ? cy + y : y
                commands.append(.cubic(x1, y1, x2, y2, ex, ey))
                lastControlX = x2
                lastControlY = y2
                cx = ex
                cy = ey
            case "S":
                guard let c = scanner.readNumber(), let dd = scanner.readNumber(),
                      let x = scanner.readNumber(), let y = scanner.readNumber() else { return commands }
                let x1: Double
                let y1: Double
                if previous == "C" || previous == "S" {
                    x1 = 2 * cx - lastControlX
                    y1 = 2 * cy - lastControlY
                } else {
                    x1 = cx
                    y1 = cy
                }
                let x2 = relative ? cx + c : c
                let y2 = relative ? cy + dd : dd
                let ex = relative ? cx + x : x
                let ey = relative ? cy + y : y
                commands.append(.cubic(x1, y1, x2, y2, ex, ey))
                lastControlX = x2
                lastControlY = y2
                cx = ex
                cy = ey
            case "Q":
                guard let a = scanner.readNumber(), let b = scanner.readNumber(),
                      let x = scanner.readNumber(), let y = scanner.readNumber() else { return commands }
                let qx = relative ? cx + a : a
                let qy = relative ? cy + b : b
                let ex = relative ? cx + x : x
                let ey = relative ? cy + y : y
                commands.append(.quad(qx, qy, ex, ey))
                lastControlX = qx
                lastControlY = qy
                cx = ex
                cy = ey
            case "T":
                guard let x = scanner.readNumber(), let y = scanner.readNumber() else { return commands }
                let qx: Double
                let qy: Double
                if previous == "Q" || previous == "T" {
                    qx = 2 * cx - lastControlX
                    qy = 2 * cy - lastControlY
                } else {
                    qx = cx
                    qy = cy
                }
                let ex = relative ? cx + x : x
                let ey = relative ? cy + y : y
                commands.append(.quad(qx, qy, ex, ey))
                lastControlX = qx
                lastControlY = qy
                cx = ex
                cy = ey
            case "A":
                guard let rx = scanner.readNumber(), let ry = scanner.readNumber(),
                      let rotation = scanner.readNumber(),
                      let large = scanner.readFlag(), let sweep = scanner.readFlag(),
                      let x = scanner.readNumber(), let y = scanner.readNumber() else { return commands }
                let ex = relative ? cx + x : x
                let ey = relative ? cy + y : y
                commands.append(contentsOf: arc(from: (cx, cy), to: (ex, ey), rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep))
                cx = ex
                cy = ey
            default:
                return commands
            }
            previous = upper
        }
        return commands
    }

    public static func arc(
        from start: (Double, Double),
        to end: (Double, Double),
        rx rxIn: Double,
        ry ryIn: Double,
        rotation: Double,
        large: Bool,
        sweep: Bool
    ) -> [PathCommand] {
        let (x1, y1) = start
        let (x2, y2) = end
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if (x1 == x2 && y1 == y2) {
            return []
        }
        if rx == 0 || ry == 0 {
            return [.line(x2, y2)]
        }
        let phi = rotation * Double.pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (x1 - x2) / 2
        let dy = (y1 - y2) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let root = lambda.squareRoot()
            rx *= root
            ry *= root
        }
        let rx2 = rx * rx
        let ry2 = ry * ry
        let numerator = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
        let denominator = rx2 * y1p * y1p + ry2 * x1p * x1p
        var coefficient = denominator == 0 ? 0 : (max(0, numerator / denominator)).squareRoot()
        if large == sweep {
            coefficient = -coefficient
        }
        let cxp = coefficient * (rx * y1p / ry)
        let cyp = coefficient * (-ry * x1p / rx)
        let centerX = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2
        let centerY = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let length = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var value = acos(max(-1, min(1, dot / length)))
            if ux * vy - uy * vx < 0 {
                value = -value
            }
            return value
        }

        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        let twoPi = 2 * Double.pi
        delta = delta.truncatingRemainder(dividingBy: twoPi)
        if !sweep && delta > 0 {
            delta -= twoPi
        } else if sweep && delta < 0 {
            delta += twoPi
        }

        let segments = max(1, Int((abs(delta) / (Double.pi / 2) - 1e-9).rounded(.up)))
        let step = delta / Double(segments)
        let t = 4.0 / 3.0 * tan(step / 4)

        func map(_ x: Double, _ y: Double) -> (Double, Double) {
            (centerX + rx * x * cosPhi - ry * y * sinPhi, centerY + rx * x * sinPhi + ry * y * cosPhi)
        }

        var result: [PathCommand] = []
        var a = theta1
        for index in 0..<segments {
            let b = a + step
            let p1 = map(cos(a) - t * sin(a), sin(a) + t * cos(a))
            let p2 = map(cos(b) + t * sin(b), sin(b) - t * cos(b))
            var p3 = map(cos(b), sin(b))
            if index == segments - 1 {
                p3 = (x2, y2)
            }
            result.append(.cubic(p1.0, p1.1, p2.0, p2.1, p3.0, p3.1))
            a = b
        }
        return result
    }

    public static func parsePoints(_ points: String) -> [(Double, Double)] {
        var scanner = Scanner(points)
        var result: [(Double, Double)] = []
        while let x = scanner.readNumber(), let y = scanner.readNumber() {
            result.append((x, y))
        }
        return result
    }
}
