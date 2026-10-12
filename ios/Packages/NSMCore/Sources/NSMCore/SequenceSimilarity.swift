import Foundation

public enum SequenceSimilarity {
    public static func ratio<T: Hashable>(_ a: [T], _ b: [T]) -> Double {
        let total = a.count + b.count
        if total == 0 {
            return 1.0
        }
        return 2.0 * Double(matchingCount(a, b)) / Double(total)
    }

    public static func ratio(_ a: String, _ b: String) -> Double {
        ratio(Array(a.unicodeScalars), Array(b.unicodeScalars))
    }

    static func matchingCount<T: Hashable>(_ a: [T], _ b: [T]) -> Int {
        if a.isEmpty || b.isEmpty {
            return 0
        }
        var b2j: [T: [Int]] = [:]
        for (index, element) in b.enumerated() {
            b2j[element, default: []].append(index)
        }
        var previous = [Int](repeating: 0, count: b.count + 1)
        var current = [Int](repeating: 0, count: b.count + 1)
        var previousTouched: [Int] = []
        var currentTouched: [Int] = []
        var stack: [(Int, Int, Int, Int)] = [(0, a.count, 0, b.count)]
        var total = 0
        while let (alo, ahi, blo, bhi) = stack.popLast() {
            var bestI = alo
            var bestJ = blo
            var bestSize = 0
            for i in alo..<ahi {
                currentTouched.removeAll(keepingCapacity: true)
                if let positions = b2j[a[i]] {
                    for j in positions {
                        if j < blo {
                            continue
                        }
                        if j >= bhi {
                            break
                        }
                        let length = previous[j] + 1
                        current[j + 1] = length
                        currentTouched.append(j + 1)
                        if length > bestSize {
                            bestI = i - length + 1
                            bestJ = j - length + 1
                            bestSize = length
                        }
                    }
                }
                for slot in previousTouched {
                    previous[slot] = 0
                }
                swap(&previous, &current)
                swap(&previousTouched, &currentTouched)
            }
            for slot in previousTouched {
                previous[slot] = 0
            }
            previousTouched.removeAll(keepingCapacity: true)
            currentTouched.removeAll(keepingCapacity: true)
            if bestSize > 0 {
                total += bestSize
                if alo < bestI && blo < bestJ {
                    stack.append((alo, bestI, blo, bestJ))
                }
                if bestI + bestSize < ahi && bestJ + bestSize < bhi {
                    stack.append((bestI + bestSize, ahi, bestJ + bestSize, bhi))
                }
            }
        }
        return total
    }
}
