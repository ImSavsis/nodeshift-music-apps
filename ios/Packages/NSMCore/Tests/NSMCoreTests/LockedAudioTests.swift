import CryptoKit
import XCTest
@testable import NSMCore

final class LockedAudioTests: XCTestCase {
    private struct Sample: Decodable {
        let keyHex: String
        let keyId: Int
        let kind: Int
        let codec: String
        let plainLength: UInt64
        let plainSha256: String
        let chunkSize: Int
        let lockedB64: String
        let ranges: [[UInt64]]
        let rangeSha256: [String]

        enum CodingKeys: String, CodingKey {
            case keyHex = "key_hex"
            case keyId = "key_id"
            case kind
            case codec
            case plainLength = "plain_length"
            case plainSha256 = "plain_sha256"
            case chunkSize = "chunk_size"
            case lockedB64 = "locked_b64"
            case ranges
            case rangeSha256 = "range_sha256"
        }
    }

    private struct LicenseSample: Decodable {
        let clientPrivateHex: String
        let clientPubB64: String
        let serverPubB64: String
        let trackId: UInt32
        let kind: UInt8
        let keyId: UInt32
        let expiresAt: UInt64
        let nonceB64: String
        let wrappedB64: String
        let contentKeyHex: String

        enum CodingKeys: String, CodingKey {
            case clientPrivateHex = "client_private_hex"
            case clientPubB64 = "client_pub_b64"
            case serverPubB64 = "server_pub_b64"
            case trackId = "track_id"
            case kind
            case keyId = "key_id"
            case expiresAt = "expires_at"
            case nonceB64 = "nonce_b64"
            case wrappedB64 = "wrapped_b64"
            case contentKeyHex = "content_key_hex"
        }
    }

    private func sample() throws -> (Sample, Data, SymmetricKey) {
        let value = try JSONDecoder().decode(Sample.self, from: TestData.data("nlac.json"))
        let locked = try XCTUnwrap(Data(base64Encoded: value.lockedB64))
        let key = SymmetricKey(data: try XCTUnwrap(Data(hex: value.keyHex)))
        return (value, locked, key)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func read(_ locked: Data, _ key: SymmetricKey, _ header: LockedHeader, _ start: UInt64, _ end: UInt64) throws -> Data {
        let span = header.span(start: start, end: end)
        let blob = locked.subdata(in: Int(span.offset)..<Int(span.offset + span.length))
        return try LockedCrypto.decrypt(key: key, header: header, span: span, blob: blob, start: start, end: end)
    }

    func testHeaderMatchesTheSharedVector() throws {
        let (value, locked, _) = try sample()
        let header = try LockedHeader(parsing: locked)
        XCTAssertEqual(header.codec, value.codec)
        XCTAssertEqual(header.plainLength, value.plainLength)
        XCTAssertEqual(Int(header.chunkSize), value.chunkSize)
        XCTAssertEqual(Int(header.keyID), value.keyId)
        XCTAssertEqual(Int(header.kind), value.kind)
        XCTAssertEqual(header.mime, "audio/flac")
    }

    func testRangesDecryptToTheExpectedBytes() throws {
        let (value, locked, key) = try sample()
        let header = try LockedHeader(parsing: locked)
        for (range, expected) in zip(value.ranges, value.rangeSha256) {
            let plain = try read(locked, key, header, range[0], range[1])
            XCTAssertEqual(UInt64(plain.count), range[1] - range[0] + 1)
            XCTAssertEqual(digest(plain), expected)
        }
        XCTAssertEqual(digest(try read(locked, key, header, 0, value.plainLength - 1)), value.plainSha256)
    }

    func testWrongKeyAndTamperingAreRejected() throws {
        var (_, locked, key) = try sample()
        let header = try LockedHeader(parsing: locked)
        XCTAssertThrowsError(try read(locked, SymmetricKey(data: Data(repeating: 9, count: 32)), header, 0, 99))
        locked[LockedHeader.size + 10] ^= 1
        XCTAssertThrowsError(try read(locked, key, header, 0, 99))
    }

    func testForeignFilesAreNotLockedAudio() {
        XCTAssertThrowsError(try LockedHeader(parsing: Data("fLaC".utf8)))
        XCTAssertThrowsError(try LockedHeader(parsing: Data(count: 64)))
    }

    func testLicenseVectorUnwrapsToTheContentKey() throws {
        let value = try JSONDecoder().decode(LicenseSample.self, from: TestData.data("license.json"))
        let exchange = try LicenseExchange(rawPrivate: try XCTUnwrap(Data(hex: value.clientPrivateHex)))
        XCTAssertEqual(exchange.publicBase64, value.clientPubB64)
        let wire = LicenseWire(
            serverPub: value.serverPubB64,
            expiresAt: value.expiresAt,
            items: [LicenseWire.Item(trackID: value.trackId, kind: "lossy", keyID: value.keyId, name: "x.np3", codec: "mp3", plainLength: 1, nonce: value.nonceB64, wrapped: value.wrappedB64)]
        )
        let grants = try exchange.open(wire)
        XCTAssertEqual(grants.first?.keyHex, value.contentKeyHex)
        XCTAssertEqual(grants.first?.kind, value.kind)
    }

    func testALicenseForAnotherTrackDoesNotOpen() throws {
        let value = try JSONDecoder().decode(LicenseSample.self, from: TestData.data("license.json"))
        let exchange = try LicenseExchange(rawPrivate: try XCTUnwrap(Data(hex: value.clientPrivateHex)))
        let wire = LicenseWire(
            serverPub: value.serverPubB64,
            expiresAt: value.expiresAt,
            items: [LicenseWire.Item(trackID: value.trackId + 1, kind: "lossy", keyID: value.keyId, name: "x.np3", codec: "mp3", plainLength: 1, nonce: value.nonceB64, wrapped: value.wrappedB64)]
        )
        XCTAssertThrowsError(try exchange.open(wire))
    }

    func testByteRanges() {
        XCTAssertEqual(ByteRange.parse("bytes=0-99", total: 1000)?.end, 99)
        XCTAssertEqual(ByteRange.parse("bytes=900-", total: 1000)?.start, 900)
        XCTAssertEqual(ByteRange.parse("bytes=900-", total: 1000)?.end, 999)
        XCTAssertEqual(ByteRange.parse("bytes=-100", total: 1000)?.start, 900)
        XCTAssertEqual(ByteRange.parse("bytes=0-5000", total: 1000)?.end, 999)
        XCTAssertNil(ByteRange.parse("bytes=2000-", total: 1000))
        XCTAssertNil(ByteRange.parse("items=0-9", total: 1000))
        XCTAssertNil(ByteRange.parse(nil, total: 1000))
    }
}
