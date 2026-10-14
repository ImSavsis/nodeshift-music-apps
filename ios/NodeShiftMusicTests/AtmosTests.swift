import XCTest
@testable import NodeShiftMusic

final class AtmosTests: XCTestCase {
    private func box(payload: [UInt8]) -> Data {
        let size = UInt32(8 + payload.count)
        var bytes: [UInt8] = [UInt8(size >> 24 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)]
        bytes.append(contentsOf: Array("dec3".utf8))
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    func testJocFlagIsDetected() {
        let data = box(payload: [0x18, 0x00, 0x20, 0x0F, 0x00, 0x01, 0x10])
        XCTAssertTrue(Dec3Probe.isJOC(in: data))
    }

    func testPlainEAC3IsNotAtmos() {
        let data = box(payload: [0x18, 0x00, 0x20, 0x0F, 0x00])
        XCTAssertFalse(Dec3Probe.isJOC(in: data))
        let flagOff = box(payload: [0x18, 0x00, 0x20, 0x0F, 0x00, 0x00, 0x00])
        XCTAssertFalse(Dec3Probe.isJOC(in: flagOff))
    }

    func testRoomLinkParsing() {
        XCTAssertEqual(MainActor.assumeIsolated { RoomStore.normalize("https://music.nodeshift.space/room/ab3k9z") }, "AB3K9Z")
        XCTAssertEqual(MainActor.assumeIsolated { RoomStore.normalize(" abc234 ") }, "ABC234")
        XCTAssertNil(MainActor.assumeIsolated { RoomStore.normalize("hello world") })
    }

    func testSoundInfo() {
        var track = TrackRecord.blank(id: "x")
        track.format = "flac"
        track.sampleRate = 96000
        track.bitDepth = 24
        let info = track.soundInfo(wantsLossless: true)
        XCTAssertEqual(info.label, "Hi-Res Lossless")
        track.format = "atmos"
        XCTAssertTrue(track.soundInfo(wantsLossless: true).isAtmos)
        XCTAssertTrue(track.usesSystemDecoder)
    }

    @MainActor
    func testLooseAlbumMatching() {
        XCTAssertEqual(EnrichmentService.looseAlbum("Travelling Without Moving (Remastered)"), EnrichmentService.looseAlbum("Travelling Without Moving"))
        XCTAssertEqual(EnrichmentService.looseAlbum("Dynamite [Deluxe]"), "dynamite")
    }
}
