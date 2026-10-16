import CryptoKit
import NSMCore
import XCTest
@testable import NodeShiftMusic

final class LockedServerTests: XCTestCase {
    private struct Sample: Decodable {
        let keyHex: String
        let keyId: UInt32
        let plainLength: UInt64
        let plainSha256: String
        let lockedB64: String
        let ranges: [[UInt64]]
        let rangeSha256: [String]
    }

    private func sample() throws -> Sample {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared")
            .appendingPathComponent("testdata")
            .appendingPathComponent("nlac.json")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Sample.self, from: Data(contentsOf: url))
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fetch(_ url: URL, range: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        if let range {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    func testTheLoopbackServerDecryptsAFileWithRanges() async throws {
        let value = try sample()
        let name = "locked-test-\(UUID().uuidString).nlac"
        let target = AppPaths.trackURL(name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(Data(base64Encoded: value.lockedB64)).write(to: target)
        defer { try? FileManager.default.removeItem(at: target) }
        let trackID: UInt32 = 424_242
        let grant = LockedGrant(
            trackID: trackID,
            kind: LockedKind.lossless.rawValue,
            keyID: value.keyId,
            name: name,
            codec: "flac",
            plainLength: value.plainLength,
            keyHex: value.keyHex,
            expiresAt: UInt64(Date().timeIntervalSince1970) + 86400
        )
        await LicenseVault.shared.remember(grant)

        let server = LockedMediaServer.shared
        server.start()
        let ready = await server.waitUntilReady()
        XCTAssertTrue(ready)
        let url = try XCTUnwrap(server.url("file/\(trackID)/lossless/\(name)"))

        let (whole, wholeResponse) = try await fetch(url)
        XCTAssertEqual(wholeResponse.statusCode, 200)
        XCTAssertEqual(wholeResponse.value(forHTTPHeaderField: "Content-Type"), "audio/flac")
        XCTAssertEqual(UInt64(whole.count), value.plainLength)
        XCTAssertEqual(digest(whole), value.plainSha256)

        for (range, expected) in zip(value.ranges, value.rangeSha256) {
            let (part, response) = try await fetch(url, range: "bytes=\(range[0])-\(range[1])")
            XCTAssertEqual(response.statusCode, 206)
            XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Range"), "bytes \(range[0])-\(range[1])/\(value.plainLength)")
            XCTAssertEqual(digest(part), expected)
        }

        let (_, beyond) = try await fetch(url, range: "bytes=99999-")
        XCTAssertEqual(beyond.statusCode, 416)
        await LicenseVault.shared.forget(trackID: trackID)
    }

    func testAWrongTokenAndAMissingLicenseGetNothing() async throws {
        let server = LockedMediaServer.shared
        server.start()
        let ready = await server.waitUntilReady()
        XCTAssertTrue(ready)
        let good = try XCTUnwrap(server.url("file/777777/lossless/missing.nlac"))
        let (_, denied) = try await fetch(good)
        XCTAssertEqual(denied.statusCode, 403)
        let wrong = try XCTUnwrap(URL(string: good.absoluteString.replacingOccurrences(of: server.token, with: "wrong")))
        let (_, missing) = try await fetch(wrong)
        XCTAssertEqual(missing.statusCode, 404)
    }
}
