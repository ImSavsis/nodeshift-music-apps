import Foundation

enum AppPaths {
    static let base: URL = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = root.appendingPathComponent("NodeShiftMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    static let caches: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

    static func directory(_ name: String, in root: URL) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var tracksDir: URL { directory("tracks", in: base) }
    static var coversDir: URL { directory("covers", in: base) }
    static var motionDir: URL { directory("motion", in: base) }
    static var thumbsDir: URL { directory("thumbs", in: base) }
    static var motionCacheDir: URL { directory("nsm-motion", in: caches) }
    static var inboxDir: URL { directory("Import", in: documents) }
    static var scratchDir: URL { directory("nsm-scratch", in: FileManager.default.temporaryDirectory) }
    static var databaseURL: URL { base.appendingPathComponent("library.sqlite") }

    static func trackURL(_ name: String) -> URL {
        tracksDir.appendingPathComponent(name)
    }

    static func coverURL(_ name: String) -> URL {
        coversDir.appendingPathComponent(name)
    }

    static func motionURL(_ name: String) -> URL {
        motionDir.appendingPathComponent(name)
    }
}
