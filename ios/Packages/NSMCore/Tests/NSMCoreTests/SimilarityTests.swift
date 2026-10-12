import XCTest
@testable import NSMCore

final class SimilarityTests: XCTestCase {
    private struct Case: Decodable {
        let name: String
        let mode: String
        let a: String
        let b: String
        let ratio: Double
    }

    func testGoldenRatiosMatchDifflib() throws {
        let cases = try JSONDecoder().decode([Case].self, from: TestData.data("similarity.json"))
        XCTAssertGreaterThan(cases.count, 20)
        for item in cases {
            let got: Double
            if item.mode == "words" {
                got = SequenceSimilarity.ratio(TextMatching.words(item.a), TextMatching.words(item.b))
            } else {
                got = SequenceSimilarity.ratio(item.a, item.b)
            }
            XCTAssertEqual(got, item.ratio, accuracy: 1e-6, item.name)
        }
    }

    func testNormalizeFoldsCaseAccentsAndBrackets() {
        XCTAssertEqual(TextMatching.normalize("Beyoncé — Halo (Live)"), "beyonce halo")
        XCTAssertEqual(TextMatching.normalize("  Hit 'Em  Up [Dirty] "), "hit em up")
        XCTAssertEqual(TextMatching.normalize("Мотив, ёлка!"), "мотив елка")
    }

    func testFeaturingIsStripped() {
        XCTAssertEqual(TextMatching.stripFeaturing("Song (feat. Someone)"), "Song")
        XCTAssertEqual(TextMatching.stripFeaturing("Eminem feat. Rihanna"), "Eminem")
        XCTAssertEqual(TextMatching.stripFeaturing("Track ft. Guest"), "Track")
        XCTAssertEqual(TextMatching.stripFeaturing("Defeat Of Me"), "Defeat Of Me")
    }

    func testArtistParts() {
        XCTAssertEqual(TextMatching.artistParts("A & B, C"), ["a", "b", "c"])
        XCTAssertEqual(TextMatching.artistParts("Solo Artist"), ["solo artist"])
    }

    func testArtistRatioUsesParts() {
        XCTAssertGreaterThan(TextMatching.artistRatio("Eminem feat. Rihanna", "Eminem"), 0.99)
        XCTAssertGreaterThan(TextMatching.artistRatio("Eminem & Dr. Dre", "Dr Dre"), 0.9)
        XCTAssertLessThan(TextMatching.artistRatio("Eminem", "Metallica"), 0.5)
    }

    func testTitleRatio() {
        XCTAssertGreaterThan(TextMatching.titleRatio("Life Goes On (Remastered 2005)", "Life Goes On"), 0.99)
        XCTAssertLessThan(TextMatching.titleRatio("Changes", "Dear Mama"), 0.5)
    }
}
