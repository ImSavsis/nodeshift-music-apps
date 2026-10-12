import Foundation
import Observation
import NSMCore

enum LyricsState: Equatable {
    case loading
    case synced([LyricLine], source: String?)
    case plain(String, source: String?)
    case none
}

@MainActor
@Observable
final class LyricsStore {
    private(set) var states: [String: LyricsState] = [:]

    func state(for track: TrackRecord) -> LyricsState {
        states[track.id] ?? .loading
    }

    func set(_ state: LyricsState, for trackID: String) {
        states[trackID] = state
    }

    func ensure(_ track: TrackRecord) async {
        if states[track.id] != nil {
            return
        }
        if track.id.hasPrefix("demo-") {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if track.id == "demo-0" || track.id == "demo-4" {
                let lines = LRCParser.parse(DemoData.lrc)
                states[track.id] = .synced(lines, source: "demo")
            } else if track.id == "demo-1" {
                states[track.id] = .plain(DemoData.lrc.split(separator: "\n").map { line in
                    String(line.drop(while: { $0 != "]" }).dropFirst())
                }.joined(separator: "\n"), source: "demo")
            } else {
                states[track.id] = LyricsState.none
            }
            return
        }
        states[track.id] = LyricsState.none
    }
}
