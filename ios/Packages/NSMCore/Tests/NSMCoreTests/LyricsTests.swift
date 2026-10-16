import XCTest
@testable import NSMCore

final class LyricsTests: XCTestCase {
    private struct LrcCase: Decodable {
        struct Line: Decodable {
            let time: Double
            let text: String
        }

        let name: String
        let lrc: String
        let expected: [Line]
    }

    private struct KaraokeCase: Decodable {
        struct Sample: Decodable {
            let t: Double
            let fills: [Double]
        }

        let text: String
        let lineTime: Double
        let nextTime: Double?
        let samples: [Sample]
    }

    func testLrcMatchesSiteParser() throws {
        let cases = try JSONDecoder().decode([LrcCase].self, from: TestData.data("lrc.json"))
        XCTAssertGreaterThan(cases.count, 4)
        for item in cases {
            let got = LRCParser.parse(item.lrc)
            XCTAssertEqual(got.count, item.expected.count, item.name)
            for (line, expected) in zip(got, item.expected) {
                XCTAssertEqual(line.time, expected.time, accuracy: 1e-9, item.name)
                XCTAssertEqual(line.text, expected.text, item.name)
                XCTAssertNil(line.words, item.name)
            }
        }
    }

    func testKaraokeFillsMatchSiteFormula() throws {
        let cases = try JSONDecoder().decode([KaraokeCase].self, from: TestData.data("karaoke.json"))
        XCTAssertGreaterThan(cases.count, 3)
        for item in cases {
            for sample in item.samples {
                let got = Karaoke.syntheticFills(text: item.text, lineTime: item.lineTime, nextTime: item.nextTime, at: sample.t)
                XCTAssertEqual(got.count, sample.fills.count, item.text)
                for (value, expected) in zip(got, sample.fills) {
                    XCTAssertEqual(value, expected, accuracy: 1e-9, "\(item.text) @ \(sample.t)")
                }
            }
        }
    }

    func testEnhancedLrcWordTiming() {
        let lrc = "[00:12.00]<00:12.00>Hello <00:12.50>big <00:13.20>world<00:14.00>\n[00:15.00]plain line"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "Hello big world")
        let words = try? XCTUnwrap(lines[0].words)
        XCTAssertEqual(words?.count, 3)
        XCTAssertEqual(words?[0].start ?? -1, 12.0, accuracy: 1e-9)
        XCTAssertEqual(words?[0].end ?? -1, 12.5, accuracy: 1e-9)
        XCTAssertEqual(words?[2].end ?? -1, 14.0, accuracy: 1e-9)
        XCTAssertNil(lines[1].words)
        XCTAssertEqual(LRCParser.kind(of: lines), .lineSynced)
        XCTAssertEqual(LRCParser.kind(of: [lines[0]]), .wordSynced)
    }

    func testLrcOffsetShiftsTimes() {
        let lines = LRCParser.parse("[offset:+500]\n[00:10.00]line")
        XCTAssertEqual(lines.first?.time ?? 0, 9.5, accuracy: 1e-9)
    }

    func testWordFillsUseRealTimingWhenPresent() {
        let line = LyricLine(
            time: 10,
            text: "a b",
            words: [LyricWord(text: "a ", start: 10, end: 11), LyricWord(text: "b", start: 11, end: 12)]
        )
        let fills = Karaoke.fills(for: line, nextTime: 14, at: 11.5)
        XCTAssertEqual(fills[0], 1, accuracy: 1e-9)
        XCTAssertEqual(fills[1], 0.5, accuracy: 1e-9)
    }

    func testActiveIndexAndStyle() {
        let lines = (0..<6).map { LyricLine(time: Double($0) * 10, text: "l\($0)") }
        XCTAssertEqual(Karaoke.activeIndex(in: lines, at: -1), -1)
        XCTAssertEqual(Karaoke.activeIndex(in: lines, at: 0), 0)
        XCTAssertEqual(Karaoke.activeIndex(in: lines, at: 25), 2)
        XCTAssertEqual(Karaoke.activeIndex(in: lines, at: 999), 5)
        XCTAssertEqual(Karaoke.style(index: 2, active: 2), Karaoke.LineStyle(opacity: 1, scale: 1, blur: 0))
        XCTAssertEqual(Karaoke.style(index: 1, active: 2), Karaoke.LineStyle(opacity: 0.38, scale: 0.93, blur: 0.55))
        XCTAssertEqual(Karaoke.style(index: 9, active: 2).blur, 3.5, accuracy: 1e-9)
    }

    private let query = LyricsQuery(title: "Ratha Be Ya Nigga", artist: "2Pac", duration: 250)

    private func candidate(
        title: String = "Ratha Be Ya Nigga",
        artist: String = "2Pac",
        duration: Double? = 250.4,
        synced: String? = "[00:10.00]one\n[03:20.00]two",
        plain: String? = nil,
        instrumental: Bool = false
    ) -> LyricsCandidate {
        LyricsCandidate(trackName: title, artistName: artist, duration: duration, synced: synced, plain: plain, instrumental: instrumental)
    }

    func testVerifierAccepts() {
        let verdict = LyricsVerifier.verify(candidate(), against: query)
        guard case let .accepted(kind, _) = verdict else {
            return XCTFail("expected accepted, got \(verdict)")
        }
        XCTAssertEqual(kind, .lineSynced)
    }

    func testVerifierRejections() {
        XCTAssertEqual(LyricsVerifier.verify(candidate(duration: 255), against: query), .rejected("duration"))
        XCTAssertEqual(LyricsVerifier.verify(candidate(title: "Changes"), against: query), .rejected("title"))
        XCTAssertEqual(LyricsVerifier.verify(candidate(artist: "Metallica"), against: query), .rejected("artist"))
        XCTAssertEqual(LyricsVerifier.verify(candidate(synced: "[05:30.00]late"), against: query), .rejected("timeline"))
        XCTAssertEqual(LyricsVerifier.verify(candidate(instrumental: true), against: query), .rejected("instrumental"))
        XCTAssertEqual(LyricsVerifier.verify(candidate(synced: nil, plain: nil), against: query), .rejected("empty"))
        XCTAssertEqual(LyricsVerifier.verify(candidate(duration: nil), against: query), .rejected("no-duration"))
        XCTAssertEqual(
            LyricsVerifier.verify(candidate(synced: nil, plain: "??? ??? ???? ???"), against: query),
            .rejected("garbled")
        )
    }

    func testVerifierAcceptsPlainWhenNoSync() {
        let verdict = LyricsVerifier.verify(candidate(synced: nil, plain: "some real words\nmore words"), against: query)
        guard case let .accepted(kind, _) = verdict else {
            return XCTFail("expected accepted, got \(verdict)")
        }
        XCTAssertEqual(kind, .plain)
    }

    func testBestPrefersWordSyncedThenLineSyncedThenPlain() {
        let plain = candidate(synced: nil, plain: "words words")
        let line = candidate()
        let word = candidate(synced: "[00:10.00]<00:10.00>one <00:11.00>two\n[03:20.00]<03:20.00>x <03:21.00>y")
        let best = LyricsVerifier.best(of: [plain, line, word], for: query)
        XCTAssertEqual(best?.kind, .wordSynced)
        XCTAssertEqual(LyricsVerifier.best(of: [plain, line], for: query)?.kind, .lineSynced)
        XCTAssertEqual(LyricsVerifier.best(of: [plain], for: query)?.kind, .plain)
        XCTAssertNil(LyricsVerifier.best(of: [candidate(title: "Other")], for: query))
    }

    func testGarbledDetection() {
        XCTAssertTrue(LyricsVerifier.isGarbled("abc \u{FFFD} def"))
        XCTAssertTrue(LyricsVerifier.isGarbled("   "))
        XCTAssertFalse(LyricsVerifier.isGarbled("Is it really you? I can't tell"))
    }

    func testPacingLearnsTheSongTempo() {
        let fast = (0..<10).map { LyricLine(time: Double($0) * 2, text: "one two three four five six seven eight") }
        let slow = (0..<10).map { LyricLine(time: Double($0) * 5, text: "one two three four") }
        XCTAssertGreaterThan(Karaoke.calibrateRate(fast), Karaoke.calibrateRate(slow))
        XCTAssertEqual(Karaoke.calibrateRate([LyricLine(time: 0, text: "a b c")]), 4)
        XCTAssertEqual(Karaoke.wordWeight("hello"), 2.2, accuracy: 1e-9)
        XCTAssertEqual(Karaoke.wordWeight("батя"), 2.2, accuracy: 1e-9)
        XCTAssertEqual(Karaoke.wordWeight("さくら"), 3.2, accuracy: 1e-9)
    }

    func testPlannedWordsStopBeforeTheNextLineAndStayContiguous() {
        var lines = (0..<8).map { LyricLine(time: Double($0) * 3, text: "we are walking down the road") }
        lines.append(LyricLine(time: 30, text: "we are walking down the road"))
        lines.append(LyricLine(time: 42, text: "the end"))
        let planned = Karaoke.planLines(lines)
        let words = planned[8].words ?? []
        XCTAssertEqual(words.first?.start ?? 0, 30, accuracy: 1e-9)
        XCTAssertLessThan(words.last?.end ?? 99, 36)
        XCTAssertGreaterThan(words.last?.end ?? 0, 31)
        for index in 1..<words.count {
            XCTAssertEqual(words[index].start, words[index - 1].end, accuracy: 1e-9)
        }
        XCTAssertTrue(words[0].text.hasSuffix(" "))
        XCTAssertFalse(words[words.count - 1].text.hasSuffix(" "))
    }

    func testRealWordTimingIsKept() {
        let real = LyricLine(time: 1, text: "a b", words: [LyricWord(text: "a ", start: 1, end: 1.2), LyricWord(text: "b", start: 1.4, end: 1.9)])
        let planned = Karaoke.planLines([real, LyricLine(time: 5, text: "c")])
        XCTAssertEqual(planned[0], real)
    }

    func testAnimationsCycleAndHonourAFixedChoice() {
        let picked = (0..<LyricAnimation.allCases.count).map { LyricAnimation.resolve(mode: "auto", index: $0, seed: 3) }
        XCTAssertEqual(Set(picked).count, LyricAnimation.allCases.count)
        XCTAssertEqual(LyricAnimation.resolve(mode: "glow", index: 5, seed: 99), .glow)
    }
}
