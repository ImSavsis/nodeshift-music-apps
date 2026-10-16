import CryptoKit
import Foundation
import Network
import NSMCore

protocol LockedByteSource: Sendable {
    func read(offset: UInt64, length: UInt64) async throws -> Data
}

struct LockedFileSource: LockedByteSource {
    let url: URL

    func read(offset: UInt64, length: UInt64) async throws -> Data {
        let target = url
        return try await Task.detached(priority: .userInitiated) {
            let handle = try FileHandle(forReadingFrom: target)
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: Int(length)), data.count == Int(length) else {
                throw LockedError.short
            }
            return data
        }.value
    }
}

struct LockedRemoteSource: LockedByteSource {
    let url: URL

    func read(offset: UInt64, length: UInt64) async throws -> Data {
        let request = Net.request(url, headers: ["Range": "bytes=\(offset)-\(offset + length - 1)"])
        let (data, response) = try await Net.session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 206, data.count == Int(length) else {
            throw NetError.invalid
        }
        return data
    }
}

struct LockedStream: Sendable {
    let header: LockedHeader
    let key: SymmetricKey
    let source: LockedByteSource

    func batch(start: UInt64, end: UInt64) async throws -> Data {
        let span = header.span(start: start, end: end)
        let blob = try await source.read(offset: span.offset, length: span.length)
        return try LockedCrypto.decrypt(key: key, header: header, span: span, blob: blob, start: start, end: end)
    }
}

final class LockedMediaServer: @unchecked Sendable {
    static let shared = LockedMediaServer()
    static let batchChunks: UInt64 = 32

    let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private let queue = DispatchQueue(label: "space.nodeshift.music.locked")
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: UInt16?

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard listener == nil else {
            return
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        guard let created = try? NWListener(using: parameters) else {
            return
        }
        created.stateUpdateHandler = { [weak self, weak created] state in
            if case .ready = state, let value = created?.port?.rawValue {
                self?.setPort(value)
            }
        }
        created.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        created.start(queue: queue)
        listener = created
    }

    private func setPort(_ value: UInt16) {
        lock.lock()
        port = value
        lock.unlock()
    }

    func url(_ route: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let port else {
            return nil
        }
        return URL(string: "http://127.0.0.1:\(port)/\(token)/\(route)")
    }

    func waitUntilReady() async -> Bool {
        for _ in 0..<200 {
            if url("x") != nil {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return url("x") != nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        Task { [weak self] in
            await self?.handle(connection)
        }
    }

    private struct Request {
        var method: String
        var path: [String]
        var range: String?
    }

    private static func parse(_ data: Data) -> Request? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let lines = text.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count >= 2 else {
            return nil
        }
        let target = first[1].split(separator: "?", omittingEmptySubsequences: false)[0]
        let path = target.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        var range: String?
        for line in lines.dropFirst() where line.lowercased().hasPrefix("range:") {
            range = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
        }
        return Request(method: String(first[0]), path: path, range: range)
    }

    private static func receive(_ connection: NWConnection) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                continuation.resume(returning: error == nil ? data : nil)
            }
        }
    }

    private static func send(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private static func redirect(_ connection: NWConnection, to target: URL) async {
        let head = "HTTP/1.1 307 Temporary Redirect\r\nLocation: \(target.absoluteString)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        try? await send(connection, Data(head.utf8))
    }

    private static func status(_ connection: NWConnection, _ line: String) async {
        let head = "HTTP/1.1 \(line)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        try? await send(connection, Data(head.utf8))
    }

    private func handle(_ connection: NWConnection) async {
        defer { connection.cancel() }
        var buffer = Data()
        let terminator = Data("\r\n\r\n".utf8)
        while buffer.range(of: terminator) == nil, buffer.count < 16384 {
            guard let more = await Self.receive(connection) else {
                return
            }
            buffer.append(more)
        }
        guard let request = Self.parse(buffer), request.path.first == token, request.method == "GET" || request.method == "HEAD" else {
            await Self.status(connection, "404 Not Found")
            return
        }
        guard let stream = try? await resolve(Array(request.path.dropFirst())) else {
            if request.path.count >= 3, request.path[1] == "site" {
                await Self.redirect(connection, to: SiteAPI.shared.previewURL(request.path[2]))
            } else {
                await Self.status(connection, "403 Forbidden")
            }
            return
        }
        await respond(connection, stream: stream, request: request)
    }

    private func respond(_ connection: NWConnection, stream: LockedStream, request: Request) async {
        let total = stream.header.plainLength
        guard total > 0 else {
            await Self.status(connection, "409 Conflict")
            return
        }
        var start: UInt64 = 0
        var end = total - 1
        var partial = false
        if let value = request.range {
            guard let parsed = ByteRange.parse(value, total: total) else {
                await Self.status(connection, "416 Range Not Satisfiable")
                return
            }
            start = parsed.start
            end = parsed.end
            partial = true
        }
        var head = partial ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: \(stream.header.mime)\r\nAccept-Ranges: bytes\r\nContent-Length: \(end - start + 1)\r\nCache-Control: no-store\r\nConnection: close\r\n"
        if partial {
            head += "Content-Range: bytes \(start)-\(end)/\(total)\r\n"
        }
        head += "\r\n"
        guard (try? await Self.send(connection, Data(head.utf8))) != nil else {
            return
        }
        if request.method == "HEAD" {
            return
        }
        let size = UInt64(stream.header.chunkSize)
        var cursor = start
        while cursor <= end {
            let last = min(end, (cursor / size + Self.batchChunks) * size - 1)
            guard let data = try? await stream.batch(start: cursor, end: last),
                  (try? await Self.send(connection, data)) != nil else {
                return
            }
            cursor = last + 1
        }
    }

    private func resolve(_ route: [String]) async throws -> LockedStream {
        guard route.count >= 3 else {
            throw LockedError.notLocked
        }
        let vault = LicenseVault.shared
        switch route[0] {
        case "site":
            var kind = route[2] == "lossless" ? LockedKind.lossless : LockedKind.lossy
            var grant: LockedGrant
            do {
                grant = try await vault.grant(siteID: route[1], kind: kind, offline: false)
            } catch {
                guard kind == .lossless else {
                    throw error
                }
                kind = .lossy
                grant = try await vault.grant(siteID: route[1], kind: kind, offline: false)
            }
            return try await stream(for: grant, source: LockedRemoteSource(url: SiteAPI.shared.lockedURL(grant.name)))
        case "file":
            guard route.count >= 4, !route[3].contains("/"), !route[3].contains("..") else {
                throw LockedError.notLocked
            }
            let kind = route[2] == "lossless" ? LockedKind.lossless : LockedKind.lossy
            let grant = try await vault.grantForPlayback(siteID: route[1], kind: kind)
            return try await stream(for: grant, source: LockedFileSource(url: AppPaths.trackURL(route[3])))
        default:
            throw LockedError.notLocked
        }
    }

    private func stream(for grant: LockedGrant, source: LockedByteSource) async throws -> LockedStream {
        let vault = LicenseVault.shared
        let header: LockedHeader
        if let known = await vault.header(for: grant.name) {
            header = known
        } else {
            header = try LockedHeader(parsing: try await source.read(offset: 0, length: UInt64(LockedHeader.size)))
            await vault.keepHeader(header, for: grant.name)
        }
        guard header.keyID == grant.keyID else {
            throw LockedError.key
        }
        return LockedStream(header: header, key: try grant.symmetricKey(), source: source)
    }
}
