import XCTest
@testable import NodeShiftMusic

private struct FakeCatalog: CatalogProviding {
    func lookup(_ query: CatalogQuery) async -> CatalogMatch? {
        if query.title.lowercased().contains("ratha") {
            return CatalogMatch(
                title: "Ratha Be Ya Nigga",
                artist: "2Pac",
                album: "All Eyez On Me",
                albumArtist: "2Pac",
                trackNumber: 9,
                discNumber: 2,
                year: 1996,
                genre: "Hip-Hop/Rap",
                isrc: "USKO10404424",
                coverURL: nil,
                durationSeconds: nil,
                source: "fake"
            )
        }
        return nil
    }

    func downloadCover(_ url: URL) async -> Data? {
        nil
    }
}

@MainActor
final class ImportPipelineTests: XCTestCase {
    private var root: URL!
    private var tracks: URL!
    private var covers: URL!
    private var scratch: URL!
    private var inputs: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("nsm-test-\(UUID().uuidString)", isDirectory: true)
        tracks = root.appendingPathComponent("tracks")
        covers = root.appendingPathComponent("covers")
        scratch = root.appendingPathComponent("scratch")
        inputs = root.appendingPathComponent("inputs")
        for url in [tracks, covers, scratch, inputs] {
            try FileManager.default.createDirectory(at: url!, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeWav(_ name: String, seconds: Double = 2, frequency: Double = 440) throws -> URL {
        let rate = 44100
        let frames = Int(Double(rate) * seconds)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + frames * 2))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(frames * 2))
        for index in 0..<frames {
            let sample = Int16(10_000 * sin(2 * Double.pi * frequency * Double(index) / Double(rate)))
            append(sample)
        }
        let url = inputs.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func makeManager(catalog: CatalogProviding?) throws -> (ImportManager, AppDatabase) {
        let database = try AppDatabase(path: nil)
        let manager = ImportManager(database: database, tracksDir: tracks, coversDir: covers, scratchDir: scratch, catalog: catalog)
        return (manager, database)
    }


    func testFilenameImportWritesTags() async throws {
        let wav = try writeWav("09 - 2pac - Ratha Be Ya Nigga.wav")
        let (manager, database) = try makeManager(catalog: FakeCatalog())
        await manager.add(urls: [wav]).value

        let saved = try database.allTracks()
        XCTAssertEqual(saved.count, 1)
        let track = try XCTUnwrap(saved.first)
        XCTAssertEqual(track.title, "Ratha Be Ya Nigga")
        XCTAssertEqual(track.artist, "2Pac")
        XCTAssertEqual(track.album, "All Eyez On Me")
        XCTAssertEqual(track.trackNumber, 9)
        XCTAssertEqual(track.discNumber, 2)
        XCTAssertLessThan(abs(track.durationMs - 2000), 80)
        XCTAssertEqual(manager.summary.added, 1)

        let written = try XCTUnwrap(TagIO.read(track.fileURLIn(tracks)))
        XCTAssertEqual(written.title, "Ratha Be Ya Nigga")
        XCTAssertEqual(written.artist, "2Pac")
        XCTAssertEqual(written.album, "All Eyez On Me")
        XCTAssertEqual(written.trackNumber, 9)
    }

    func testBatchNumberingWithoutCatalog() async throws {
        let first = try writeWav("01. Intro.wav", frequency: 300)
        let second = try writeWav("02. Hurt.wav", frequency: 500)
        let third = try writeWav("03. Dear Mama.wav", frequency: 700)
        let (manager, database) = try makeManager(catalog: nil)
        await manager.add(urls: [first, second, third]).value

        let saved = try database.allTracks().sorted { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }
        XCTAssertEqual(saved.map { $0.title }, ["Intro", "Hurt", "Dear Mama"])
        XCTAssertEqual(saved.map { $0.trackNumber }, [1, 2, 3])
        XCTAssertTrue(saved.allSatisfy { $0.artist == "Неизвестный исполнитель" })
    }

    func testSameFileIsSkipped() async throws {
        let wav = try writeWav("Artist - Song.wav")
        let (manager, database) = try makeManager(catalog: nil)
        await manager.add(urls: [wav]).value
        XCTAssertEqual(try database.allTracks().count, 1)

        await manager.add(urls: [wav]).value
        XCTAssertEqual(try database.allTracks().count, 1)
        XCTAssertEqual(manager.summary.duplicates, 1)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: tracks.path)
        XCTAssertEqual(leftovers.count, 1)
    }

    func testSameTrackDifferentBytesAsksForDecision() async throws {
        let original = try writeWav("Artist - Song.wav", seconds: 2, frequency: 440)
        let (manager, database) = try makeManager(catalog: nil)
        await manager.add(urls: [original]).value

        let other = inputs.appendingPathComponent("again")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let copy = try writeWav("Artist - Song.wav", seconds: 2, frequency: 880)
        let moved = other.appendingPathComponent("Artist - Song.wav")
        try FileManager.default.moveItem(at: copy, to: moved)
        await manager.add(urls: [moved]).value

        XCTAssertEqual(try database.allTracks().count, 1)
        XCTAssertEqual(manager.pendingDuplicates, 1)
        let waiting = try XCTUnwrap(manager.items.last)
        guard case .duplicate = waiting.state else {
            return XCTFail("expected duplicate state, got \(waiting.state)")
        }
        manager.decide(waiting.id, .keepBoth)
        XCTAssertEqual(try database.allTracks().count, 2)
    }

    func testFolderImportGroupsByFolderForBatchParsing() async throws {
        let album = inputs.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        for (index, name) in ["Alpha", "Beta", "Gamma"].enumerated() {
            let file = try writeWav("\(String(format: "%02d", index + 1)) - Band - \(name).wav", frequency: 300 + Double(index) * 100)
            try FileManager.default.moveItem(at: file, to: album.appendingPathComponent(file.lastPathComponent))
        }
        let (manager, database) = try makeManager(catalog: nil)
        await manager.add(urls: [album]).value
        let saved = try database.allTracks().sorted { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }
        XCTAssertEqual(saved.map { $0.title }, ["Alpha", "Beta", "Gamma"])
        XCTAssertTrue(saved.allSatisfy { $0.artist == "Band" })
    }
}

private extension TrackRecord {
    func fileURLIn(_ directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }
}
