import XCTest
@testable import NodeShiftMusic

final class ServiceParsingTests: XCTestCase {
    private func sample(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("shared/testdata/\(name)"), encoding: .utf8)
    }

    func testSiteTrackDecodesNumericAndStringIds() throws {
        let json = """
        [
          {"id": 53, "title": "T", "artist": "A", "album": null, "duration_seconds": 201.5, "filename": "x.flac",
           "cover_filename": "c.jpg", "motion_filename": null, "stream_filename": "x.m4a", "media_kind": "audio",
           "format": "flac", "play_count": 3, "uploader_id": 9, "created_at": "2026-10-01T10:00:00"},
          {"id": "abc", "title": "U", "artist": "B", "filename": "y.mp3", "format": "mp3"}
        ]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tracks = try decoder.decode([SiteTrack].self, from: Data(json.utf8))
        XCTAssertEqual(tracks.map { $0.id.value }, ["53", "abc"])
        XCTAssertEqual(tracks[0].durationSeconds, 201.5)
        XCTAssertEqual(tracks[0].streamFilename, "x.m4a")
        XCTAssertNil(tracks[1].coverFilename)
    }

    func testPlaylistDetailDecodes() throws {
        let json = """
        {"id": 7, "name": "Mix", "cover_filename": null, "owner_id": 1, "created_at": "2026-10-01T10:00:00",
         "tracks": [{"position": 1, "track": {"id": 2, "title": "B", "artist": "X", "filename": "b.flac"}},
                    {"position": 0, "track": {"id": 1, "title": "A", "artist": "X", "filename": "a.flac"}}]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(SitePlaylistDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.id.value, "7")
        XCTAssertEqual(detail.tracks.sorted { $0.position < $1.position }.map { $0.track.title }, ["A", "B"])
    }

    func testHlsVariantSelectionPrefersAvc1Near960() throws {
        let master = try sample("hls-master.m3u8")
        let base = URL(string: "https://mvod.itunes.apple.com/itunes-assets/x/master.m3u8")!
        let variants = MotionCoverFinder.parseVariants(master: master, base: base)
        XCTAssertGreaterThan(variants.count, 3)
        XCTAssertTrue(variants.allSatisfy { $0.url.absoluteString.hasPrefix("https://") })
        let picked = try XCTUnwrap(MotionCoverFinder.pickVariant(variants))
        XCTAssertEqual(picked.width, 960)
    }

    func testHlsMapURIResolvesRelativeToVariant() throws {
        let variant = try sample("hls-variant.m3u8")
        let base = URL(string: "https://mvod.itunes.apple.com/itunes-assets/HLSMusic122/v4/16/7d/x/var960.m3u8")!
        let file = try XCTUnwrap(MotionCoverFinder.mapURI(variantPlaylist: variant, base: base))
        XCTAssertEqual(file.lastPathComponent, "P512769495_Anull_video_gr250_sdr_960x960_-.mp4")
        XCTAssertEqual(file.host, "mvod.itunes.apple.com")
    }

    func testCollectVideosFindsSquareAndTall() throws {
        let json = """
        {"data": [{"data": {"sections": [{"items": [{"videoArtwork": {"dictionary": {"motionDetailSquare": {"video": "https://a/sq.m3u8"}}},
         "tallVideoArtwork": {"dictionary": {"motionDetailTall": {"video": "https://a/tall.m3u8"}}}}]}]}}]}
        """
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        var found: [String: String] = [:]
        MotionCoverFinder.collectVideos(object, into: &found)
        XCTAssertEqual(found["square"], "https://a/sq.m3u8")
        XCTAssertEqual(found["tall"], "https://a/tall.m3u8")
    }

    func testCatalogScoring() {
        let query = CatalogQuery(title: "Ratha Be Ya Nigga", artist: "2pac", album: nil, duration: 250)
        XCTAssertNotNil(CatalogClient.score(query: query, title: "Ratha Be Ya Nigga", artist: "2Pac", duration: 251))
        XCTAssertNil(CatalogClient.score(query: query, title: "Changes", artist: "2Pac", duration: 251))
        XCTAssertNil(CatalogClient.score(query: query, title: "Ratha Be Ya Nigga", artist: "Metallica", duration: 251))
        XCTAssertNil(CatalogClient.score(query: query, title: "Ratha Be Ya Nigga", artist: "2Pac", duration: 300))
        let titleOnly = CatalogQuery(title: "Ratha Be Ya Nigga", artist: "", album: nil, duration: 250)
        XCTAssertNotNil(CatalogClient.score(query: titleOnly, title: "Ratha Be Ya Nigga", artist: "2Pac", duration: 250.5))
        XCTAssertNil(CatalogClient.score(query: titleOnly, title: "Ratha Be Ya Nigga", artist: "2Pac", duration: 254))
    }

    func testArtworkURLUpscale() {
        let url = CatalogClient.artworkURL("https://is1-ssl.mzstatic.com/image/thumb/Music/x/100x100bb.jpg")
        XCTAssertEqual(url?.absoluteString, "https://is1-ssl.mzstatic.com/image/thumb/Music/x/1400x1400bb.jpg")
    }

    func testPluralTracks() {
        XCTAssertEqual(pluralTracks(1), "1 трек")
        XCTAssertEqual(pluralTracks(2), "2 трека")
        XCTAssertEqual(pluralTracks(5), "5 треков")
        XCTAssertEqual(pluralTracks(11), "11 треков")
        XCTAssertEqual(pluralTracks(21), "21 трек")
        XCTAssertEqual(pluralTracks(112), "112 треков")
    }

    func testClockFormat() {
        XCTAssertEqual(formatClock(0), "0:00")
        XCTAssertEqual(formatClock(65.9), "1:05")
        XCTAssertEqual(formatClock(3599), "59:59")
    }
}
