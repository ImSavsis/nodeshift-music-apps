import Foundation

public struct AppVersion: Comparable, Hashable, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        if text.isEmpty {
            return nil
        }
        var parsed: [Int] = []
        for piece in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard let value = Int(piece), value >= 0 else { return nil }
            parsed.append(value)
        }
        components = parsed
    }

    private static func padded(_ a: [Int], _ b: [Int]) -> ([Int], [Int]) {
        let count = max(a.count, b.count)
        return (
            a + [Int](repeating: 0, count: count - a.count),
            b + [Int](repeating: 0, count: count - b.count)
        )
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let (a, b) = padded(lhs.components, rhs.components)
        return a == b
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let (a, b) = padded(lhs.components, rhs.components)
        for (x, y) in zip(a, b) where x != y {
            return x < y
        }
        return false
    }

    public func hash(into hasher: inout Hasher) {
        var trimmed = components
        while trimmed.last == 0 {
            trimmed.removeLast()
        }
        hasher.combine(trimmed)
    }
}

public struct UpdateManifest: Codable, Equatable, Sendable {
    public var platform: String
    public var version: String
    public var build: Int
    public var commit: String?
    public var file: String
    public var size: Int
    public var sha256: String
    public var minOS: String?
    public var notes: String?
    public var builtAt: String?
    public var url: String?

    public init(
        platform: String,
        version: String,
        build: Int,
        commit: String? = nil,
        file: String,
        size: Int,
        sha256: String,
        minOS: String? = nil,
        notes: String? = nil,
        builtAt: String? = nil,
        url: String? = nil
    ) {
        self.platform = platform
        self.version = version
        self.build = build
        self.commit = commit
        self.file = file
        self.size = size
        self.sha256 = sha256
        self.minOS = minOS
        self.notes = notes
        self.builtAt = builtAt
        self.url = url
    }
}

public enum UpdateCheck {
    public static func isNewer(_ manifest: UpdateManifest, currentVersion: String, currentBuild: Int) -> Bool {
        guard let remote = AppVersion(manifest.version), let local = AppVersion(currentVersion) else {
            return manifest.build > currentBuild
        }
        if remote != local {
            return remote > local
        }
        return manifest.build > currentBuild
    }

    public static func meetsMinimumOS(_ manifest: UpdateManifest, current: String) -> Bool {
        guard let required = manifest.minOS, let need = AppVersion(required), let have = AppVersion(current) else {
            return true
        }
        return have >= need
    }
}
