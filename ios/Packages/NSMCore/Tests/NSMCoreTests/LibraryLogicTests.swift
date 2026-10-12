import XCTest
@testable import NSMCore

final class LibraryLogicTests: XCTestCase {
    private struct PaletteCase: Decodable {
        let name: String
        let rgbaBase64: String
        let expected: [[Int]]
    }

    func testPaletteMatchesSiteAlgorithm() throws {
        let cases = try JSONDecoder().decode([PaletteCase].self, from: TestData.data("palette.json"))
        XCTAssertGreaterThan(cases.count, 5)
        for item in cases {
            let data = try XCTUnwrap(Data(base64Encoded: item.rgbaBase64), item.name)
            let got = PaletteExtractor.extract(rgba: [UInt8](data)).map { [$0.r, $0.g, $0.b] }
            XCTAssertEqual(got, item.expected, item.name)
        }
    }

    func testPaletteFallbackOnEmptyInput() {
        XCTAssertEqual(PaletteExtractor.extract(rgba: []), PaletteExtractor.fallback)
    }

    func testDuplicateSameFile() {
        let index = DuplicateIndex([TrackFingerprint(id: "a", artist: "X", title: "Y", fileHash: "abc", format: "flac")])
        let hits = index.matches(for: TrackFingerprint(id: "new", artist: "Other", title: "Other", fileHash: "abc", format: "mp3"))
        XCTAssertEqual(hits.map { $0.kind }, [.sameFile])
    }

    func testDuplicateSameTrackDifferentFormat() {
        let existing = TrackFingerprint(id: "a", artist: "2Pac", title: "Ratha Be Ya Nigga", durationMs: 250_000, format: "mp3", bitrateKbps: 128)
        let index = DuplicateIndex([existing])
        let candidate = TrackFingerprint(id: "n", artist: "2pac", title: "Ratha Be Ya Nigga (Remastered)", durationMs: 250_800, format: "flac")
        let hits = index.matches(for: candidate)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.kind, .sameTrack)
        XCTAssertEqual(hits.first?.candidateIsBetterQuality, true)
    }

    func testDuplicateIgnoresFeaturingAndRespectsDuration() {
        let index = DuplicateIndex([TrackFingerprint(id: "a", artist: "Eminem", title: "Stan", durationMs: 404_000, format: "flac")])
        let featuring = TrackFingerprint(id: "n", artist: "Eminem feat. Dido", title: "Stan (feat. Dido)", durationMs: 404_500, format: "flac")
        XCTAssertEqual(index.matches(for: featuring).first?.kind, .sameTrack)
        let different = TrackFingerprint(id: "n2", artist: "Eminem", title: "Stan", durationMs: 480_000, format: "flac")
        XCTAssertTrue(index.matches(for: different).isEmpty)
    }

    func testDuplicateSimilarTitle() {
        let index = DuplicateIndex([TrackFingerprint(id: "a", artist: "Artist", title: "Midnight Rain Falling", durationMs: 200_000, format: "mp3", bitrateKbps: 320)])
        let hits = index.matches(for: TrackFingerprint(id: "n", artist: "Artist", title: "Midnight Rain Fallin", durationMs: 201_000, format: "mp3", bitrateKbps: 320))
        XCTAssertEqual(hits.first?.kind, .similar)
    }

    func testDuplicateRemove() {
        var index = DuplicateIndex([TrackFingerprint(id: "a", artist: "X", title: "Y", durationMs: 1000, fileHash: "h", format: "flac")])
        index.remove(id: "a")
        XCTAssertTrue(index.matches(for: TrackFingerprint(id: "n", artist: "X", title: "Y", durationMs: 1000, fileHash: "h", format: "flac")).isEmpty)
    }

    func testQualityRank() {
        XCTAssertGreaterThan(QualityRank.score(format: "FLAC", bitrateKbps: nil), QualityRank.score(format: "mp3", bitrateKbps: 320))
        XCTAssertGreaterThan(QualityRank.score(format: "mp3", bitrateKbps: 320), QualityRank.score(format: "mp3", bitrateKbps: 128))
    }

    func testVersionComparison() throws {
        let a = try XCTUnwrap(AppVersion("1.10.0"))
        let b = try XCTUnwrap(AppVersion("1.9.9"))
        XCTAssertTrue(a > b)
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))
        XCTAssertEqual(AppVersion("v2.1")?.components, [2, 1])
        XCTAssertNil(AppVersion("1.x"))
        XCTAssertNil(AppVersion(""))
    }

    func testUpdateCheck() {
        let manifest = UpdateManifest(platform: "ios", version: "0.2.0", build: 5, file: "x.ipa", size: 1, sha256: "s", minOS: "17.0")
        XCTAssertTrue(UpdateCheck.isNewer(manifest, currentVersion: "0.1.0", currentBuild: 99))
        XCTAssertTrue(UpdateCheck.isNewer(manifest, currentVersion: "0.2.0", currentBuild: 4))
        XCTAssertFalse(UpdateCheck.isNewer(manifest, currentVersion: "0.2.0", currentBuild: 5))
        XCTAssertFalse(UpdateCheck.isNewer(manifest, currentVersion: "0.3.0", currentBuild: 1))
        XCTAssertTrue(UpdateCheck.meetsMinimumOS(manifest, current: "17.4"))
        XCTAssertFalse(UpdateCheck.meetsMinimumOS(manifest, current: "16.7"))
    }

    func testManifestDecodesFromCi() throws {
        let json = """
        {"platform":"ios","version":"0.1.0","build":1,"commit":"abc","file":"NodeShiftMusic.ipa","size":5089643,"sha256":"971b","minOS":"17.0","notes":"n","builtAt":"2026-10-12T20:26:30Z"}
        """
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.build, 1)
        XCTAssertEqual(manifest.size, 5_089_643)
        XCTAssertNil(manifest.url)
    }
}
