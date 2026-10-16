import CryptoKit
import Foundation

public enum LockedKind: UInt8, Sendable {
    case lossless = 1
    case lossy = 2

    public var name: String {
        self == .lossless ? "lossless" : "lossy"
    }
}

public enum LockedError: Error, Equatable {
    case notLocked
    case authentication
    case short
    case key
}

public struct LockedSpan: Equatable, Sendable {
    public var firstChunk: UInt64
    public var lastChunk: UInt64
    public var offset: UInt64
    public var length: UInt64
}

public struct LockedHeader: Equatable, Sendable {
    public static let size = 64
    public static let tagSize = 16

    public let kind: UInt8
    public let codec: String
    public let keyID: UInt32
    public let chunkSize: UInt32
    public let plainLength: UInt64
    public let noncePrefix: Data
    public let raw: Data

    public init(parsing input: Data) throws {
        let data = Data(input)
        guard data.count >= Self.size else {
            throw LockedError.short
        }
        guard data.prefix(4) == Data("NSML".utf8), data[4] == 1, data[5] == 1 || data[5] == 2 else {
            throw LockedError.notLocked
        }
        let chunk = Self.readUInt32(data, at: 20)
        guard chunk > 0 else {
            throw LockedError.notLocked
        }
        kind = data[5]
        codec = String(decoding: data.subdata(in: 8..<16).prefix { $0 != 0 }, as: UTF8.self)
        keyID = Self.readUInt32(data, at: 16)
        chunkSize = chunk
        plainLength = Self.readUInt64(data, at: 24)
        noncePrefix = data.subdata(in: 32..<40)
        raw = data.subdata(in: 0..<Self.size)
    }

    static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<(offset + 4)).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        data.subdata(in: offset..<(offset + 8)).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    public var stride: UInt64 {
        UInt64(chunkSize) + UInt64(Self.tagSize)
    }

    public var chunkCount: UInt64 {
        (plainLength + UInt64(chunkSize) - 1) / UInt64(chunkSize)
    }

    public var mime: String {
        switch codec {
        case "flac": return "audio/flac"
        case "aac", "m4a", "alac": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "ogg", "opus": return "audio/ogg"
        case "aiff", "aif": return "audio/aiff"
        default: return "application/octet-stream"
        }
    }

    public func span(start: UInt64, end: UInt64) -> LockedSpan {
        let size = UInt64(chunkSize)
        let first = start / size
        let last = end / size
        let from = UInt64(Self.size) + first * stride
        let total = UInt64(Self.size) + plainLength + chunkCount * UInt64(Self.tagSize)
        let until = min(UInt64(Self.size) + (last + 1) * stride, total)
        return LockedSpan(firstChunk: first, lastChunk: last, offset: from, length: until - from)
    }

    public func nonce(for index: UInt64) throws -> AES.GCM.Nonce {
        var bytes = noncePrefix
        bytes.append(contentsOf: Self.bigEndian(UInt32(truncatingIfNeeded: index)))
        return try AES.GCM.Nonce(data: bytes)
    }

    public func associatedData(for index: UInt64) -> Data {
        var bytes = raw
        bytes.append(contentsOf: Self.bigEndian(UInt32(truncatingIfNeeded: index)))
        return bytes
    }

    static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    }

    static func bigEndian(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8((value >> UInt64((7 - $0) * 8)) & 0xff) }
    }
}

public enum LockedCrypto {
    public static func decrypt(key: SymmetricKey, header: LockedHeader, span: LockedSpan, blob: Data, start: UInt64, end: UInt64) throws -> Data {
        let stride = Int(header.stride)
        var plain = Data()
        var position = 0
        var index = span.firstChunk
        let source = Data(blob)
        while position < source.count {
            let piece = source.subdata(in: position..<min(position + stride, source.count))
            guard piece.count > LockedHeader.tagSize else {
                throw LockedError.short
            }
            let body = piece.subdata(in: 0..<(piece.count - LockedHeader.tagSize))
            let tag = piece.subdata(in: (piece.count - LockedHeader.tagSize)..<piece.count)
            do {
                let box = try AES.GCM.SealedBox(nonce: header.nonce(for: index), ciphertext: body, tag: tag)
                plain.append(try AES.GCM.open(box, using: key, authenticating: header.associatedData(for: index)))
            } catch {
                throw LockedError.authentication
            }
            position += stride
            index += 1
        }
        let skip = Int(start - span.firstChunk * UInt64(header.chunkSize))
        let take = Int(end - start + 1)
        guard plain.count >= skip + take else {
            throw LockedError.short
        }
        return plain.subdata(in: skip..<(skip + take))
    }
}

public enum ByteRange {
    public static func parse(_ header: String?, total: UInt64) -> (start: UInt64, end: UInt64)? {
        guard let header, total > 0 else {
            return nil
        }
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("bytes=") else {
            return nil
        }
        let parts = trimmed.dropFirst(6).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }
        if parts[0].isEmpty {
            guard let suffix = UInt64(parts[1]) else {
                return nil
            }
            return (total > suffix ? total - suffix : 0, total - 1)
        }
        guard let start = UInt64(parts[0]) else {
            return nil
        }
        let end: UInt64
        if parts[1].isEmpty {
            end = total - 1
        } else if let value = UInt64(parts[1]) {
            end = min(value, total - 1)
        } else {
            return nil
        }
        return start <= end && start < total ? (start, end) : nil
    }
}

public struct LockedGrant: Codable, Equatable, Sendable {
    public var trackID: UInt32
    public var kind: UInt8
    public var keyID: UInt32
    public var name: String
    public var codec: String
    public var plainLength: UInt64
    public var keyHex: String
    public var expiresAt: UInt64

    public init(trackID: UInt32, kind: UInt8, keyID: UInt32, name: String, codec: String, plainLength: UInt64, keyHex: String, expiresAt: UInt64) {
        self.trackID = trackID
        self.kind = kind
        self.keyID = keyID
        self.name = name
        self.codec = codec
        self.plainLength = plainLength
        self.keyHex = keyHex
        self.expiresAt = expiresAt
    }

    public func symmetricKey() throws -> SymmetricKey {
        guard let bytes = Data(hex: keyHex), bytes.count == 32 else {
            throw LockedError.key
        }
        return SymmetricKey(data: bytes)
    }
}

public struct LicenseWire: Decodable, Sendable {
    public struct Item: Decodable, Sendable {
        public var trackID: UInt32
        public var kind: String
        public var keyID: UInt32
        public var name: String
        public var codec: String
        public var plainLength: UInt64
        public var nonce: String
        public var wrapped: String

        public init(trackID: UInt32, kind: String, keyID: UInt32, name: String, codec: String, plainLength: UInt64, nonce: String, wrapped: String) {
            self.trackID = trackID
            self.kind = kind
            self.keyID = keyID
            self.name = name
            self.codec = codec
            self.plainLength = plainLength
            self.nonce = nonce
            self.wrapped = wrapped
        }

        enum CodingKeys: String, CodingKey {
            case trackID = "track_id"
            case kind
            case keyID = "key_id"
            case name
            case codec
            case plainLength = "plain_length"
            case nonce
            case wrapped
        }
    }

    public var serverPub: String
    public var expiresAt: UInt64
    public var items: [Item]

    public init(serverPub: String, expiresAt: UInt64, items: [Item]) {
        self.serverPub = serverPub
        self.expiresAt = expiresAt
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case serverPub = "server_pub"
        case expiresAt = "expires_at"
        case items
    }
}

public struct LicenseExchange {
    private let secret: P256.KeyAgreement.PrivateKey

    public init() {
        secret = P256.KeyAgreement.PrivateKey()
    }

    public init(rawPrivate: Data) throws {
        secret = try P256.KeyAgreement.PrivateKey(rawRepresentation: rawPrivate)
    }

    public var publicBytes: Data {
        secret.publicKey.x963Representation
    }

    public var publicBase64: String {
        publicBytes.base64EncodedString()
    }

    public func open(_ wire: LicenseWire) throws -> [LockedGrant] {
        guard let serverBytes = Data(base64Encoded: wire.serverPub),
              let serverKey = try? P256.KeyAgreement.PublicKey(x963Representation: serverBytes),
              let shared = try? secret.sharedSecretFromKeyAgreement(with: serverKey) else {
            throw LockedError.key
        }
        var salt = publicBytes
        salt.append(serverBytes)
        let wrapKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("NSM-LICENSE-1".utf8), outputByteCount: 32)
        var grants: [LockedGrant] = []
        for item in wire.items {
            let kind: UInt8 = item.kind == "lossless" ? LockedKind.lossless.rawValue : LockedKind.lossy.rawValue
            var context = Data("NSM-L1".utf8)
            context.append(contentsOf: LockedHeader.bigEndian(item.trackID))
            context.append(kind)
            context.append(contentsOf: LockedHeader.bigEndian(item.keyID))
            context.append(contentsOf: LockedHeader.bigEndian(wire.expiresAt))
            guard let nonceBytes = Data(base64Encoded: item.nonce), let wrapped = Data(base64Encoded: item.wrapped), wrapped.count > LockedHeader.tagSize else {
                throw LockedError.key
            }
            do {
                let box = try AES.GCM.SealedBox(
                    nonce: AES.GCM.Nonce(data: nonceBytes),
                    ciphertext: wrapped.subdata(in: 0..<(wrapped.count - LockedHeader.tagSize)),
                    tag: wrapped.subdata(in: (wrapped.count - LockedHeader.tagSize)..<wrapped.count)
                )
                let content = try AES.GCM.open(box, using: wrapKey, authenticating: context)
                grants.append(
                    LockedGrant(
                        trackID: item.trackID,
                        kind: kind,
                        keyID: item.keyID,
                        name: item.name,
                        codec: item.codec,
                        plainLength: item.plainLength,
                        keyHex: content.map { String(format: "%02x", $0) }.joined(),
                        expiresAt: wire.expiresAt
                    )
                )
            } catch {
                throw LockedError.authentication
            }
        }
        return grants
    }
}

extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else {
            return nil
        }
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
