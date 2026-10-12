import Foundation
import GRDB
import SFBAudioEngine
import NSMCore

enum EngineProbe {
    static func summary() -> String {
        let formats = AudioFile.supportedPathExtensions.sorted().joined(separator: " ")
        let database = (try? DatabaseQueue()) != nil
        let parsed = FilenameParser.parse("09 - 2pac - Ratha Be Ya Nigga.flac", numberedBatch: false)
        return "db \(database) · \(parsed.track ?? 0) \(parsed.artist ?? "?") · \(formats)"
    }
}
