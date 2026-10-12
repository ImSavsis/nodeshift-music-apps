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

    @ObservationIgnored var database: AppDatabase?
    @ObservationIgnored private var inFlight: Set<String> = []

    func state(for track: TrackRecord) -> LyricsState {
        states[track.id] ?? .loading
    }

    func ensure(_ track: TrackRecord) async {
        if states[track.id] != nil || inFlight.contains(track.id) {
            return
        }
        inFlight.insert(track.id)
        defer { inFlight.remove(track.id) }
        if track.id.hasPrefix("demo-") {
            await ensureDemo(track)
            return
        }
        if let stored = stored(for: track) {
            states[track.id] = stored
            return
        }
        await resolve(track, force: false)
    }

    func refresh(_ track: TrackRecord) async {
        states[track.id] = .loading
        inFlight.insert(track.id)
        defer { inFlight.remove(track.id) }
        await resolve(track, force: true)
    }

    private func stored(for track: TrackRecord) -> LyricsState? {
        guard let database, let record = try? database.lyrics(trackId: track.id) else { return nil }
        switch record.kind {
        case "word", "line":
            guard let lrc = record.lrc else { return nil }
            let lines = LRCParser.parse(lrc)
            return lines.isEmpty ? nil : .synced(lines, source: record.source)
        case "plain":
            guard let plain = record.plain, !plain.isEmpty else { return nil }
            return .plain(plain, source: record.source)
        default:
            if Date().timeIntervalSince(record.checkedAt) < 12 * 3600 {
                return LyricsState.none
            }
            return nil
        }
    }

    private func save(_ track: TrackRecord, kind: String, source: String, lrc: String?, plain: String?) {
        guard let database else { return }
        let record = LyricsRecord(trackId: track.id, kind: kind, source: source, lrc: lrc, plain: plain, checkedAt: Date())
        try? database.save(record)
    }

    private func resolve(_ track: TrackRecord, force: Bool) async {
        let url = track.fileURL
        if !force {
            let embedded = await Task.detached(priority: .utility) {
                TagIO.read(url)?.lyrics
            }.value
            if let text = embedded, !text.isEmpty {
                let lines = LRCParser.parse(text)
                if lines.count >= 2 {
                    let kind = LRCParser.kind(of: lines) == .wordSynced ? "word" : "line"
                    save(track, kind: kind, source: "embedded", lrc: text, plain: nil)
                    states[track.id] = .synced(lines, source: "embedded")
                } else {
                    save(track, kind: "plain", source: "embedded", lrc: nil, plain: text)
                    states[track.id] = .plain(text, source: "embedded")
                }
                return
            }
        }
        let duration = track.durationMs > 0 ? track.durationSeconds : nil
        guard let found = await LyricsClient.fetch(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: duration
        ) else {
            save(track, kind: "none", source: "none", lrc: nil, plain: nil)
            states[track.id] = LyricsState.none
            return
        }
        switch found.kind {
        case .wordSynced, .lineSynced:
            let lines = found.lrc.map { LRCParser.parse($0) } ?? []
            if lines.isEmpty, let plain = found.plain {
                save(track, kind: "plain", source: found.source, lrc: nil, plain: plain)
                states[track.id] = .plain(plain, source: found.source)
            } else {
                save(track, kind: found.kind == .wordSynced ? "word" : "line", source: found.source, lrc: found.lrc, plain: found.plain)
                states[track.id] = .synced(lines, source: found.source)
            }
        case .plain:
            let plain = found.plain ?? ""
            save(track, kind: "plain", source: found.source, lrc: nil, plain: plain)
            states[track.id] = .plain(plain, source: found.source)
        case .none:
            save(track, kind: "none", source: "none", lrc: nil, plain: nil)
            states[track.id] = LyricsState.none
        }
    }

    private func ensureDemo(_ track: TrackRecord) async {
        try? await Task.sleep(nanoseconds: 250_000_000)
        if track.id == "demo-0" || track.id == "demo-4" {
            states[track.id] = .synced(LRCParser.parse(DemoData.lrc), source: "demo")
        } else if track.id == "demo-1" {
            let plain = DemoData.lrc
                .split(separator: "\n")
                .map { String($0.drop(while: { $0 != "]" }).dropFirst()) }
                .joined(separator: "\n")
            states[track.id] = .plain(plain, source: "demo")
        } else {
            states[track.id] = LyricsState.none
        }
    }
}
