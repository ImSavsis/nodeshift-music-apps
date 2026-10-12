import XCTest
@testable import NSMCore

final class FilenameParserTests: XCTestCase {
    private struct Case: Decodable {
        struct Expected: Decodable {
            let disc: Int?
            let track: Int?
            let artist: String?
            let title: String?
        }

        let label: String
        let names: [String]
        let numbered: Bool
        let expected: [Expected]
    }

    private func loadCases() throws -> [Case] {
        try JSONDecoder().decode([Case].self, from: TestData.data("filename-parser.json"))
    }

    func testVectorsHaveCases() throws {
        XCTAssertGreaterThan(try loadCases().count, 10)
    }

    func testBatchDetection() throws {
        for item in try loadCases() {
            XCTAssertEqual(FilenameParser.isNumberedBatch(item.names), item.numbered, item.label)
        }
    }

    func testParsingMatchesVectors() throws {
        for item in try loadCases() {
            let numbered = FilenameParser.isNumberedBatch(item.names)
            XCTAssertEqual(item.names.count, item.expected.count, item.label)
            for (name, expected) in zip(item.names, item.expected) {
                let got = FilenameParser.parse(name, numberedBatch: numbered)
                XCTAssertEqual(got.disc, expected.disc, "\(item.label): \(name) disc")
                XCTAssertEqual(got.track, expected.track, "\(item.label): \(name) track")
                XCTAssertEqual(got.artist, expected.artist, "\(item.label): \(name) artist")
                XCTAssertEqual(got.title, expected.title, "\(item.label): \(name) title")
            }
        }
    }

    func testUserExample() {
        let parsed = FilenameParser.parse("09 - 2pac - Ratha Be Ya Nigga.flac", numberedBatch: false)
        XCTAssertEqual(parsed, ParsedName(disc: nil, track: 9, artist: "2pac", title: "Ratha Be Ya Nigga"))
    }

    func testBatchHelper() {
        let parsed = FilenameParser.parseBatch(["01. Intro.flac", "02. Hurt.flac", "03. Dear Mama.flac"])
        XCTAssertEqual(parsed.map { $0.track }, [1, 2, 3])
        XCTAssertEqual(parsed.map { $0.title }, ["Intro", "Hurt", "Dear Mama"])
        XCTAssertTrue(parsed.allSatisfy { $0.artist == nil })
    }
}
