import Foundation

actor RateLimiter {
    static let shared = RateLimiter()

    private var nextSlot: [String: Date] = [:]

    func wait(_ key: String, interval: TimeInterval) async {
        let now = Date()
        let slot = max(now, nextSlot[key] ?? now)
        nextSlot[key] = slot.addingTimeInterval(interval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}

enum NetError: Error {
    case status(Int)
    case notFound
    case invalid
}

enum Net {
    static let userAgent = "NodeShiftMusic/0.1 (+https://music.nodeshift.space)"
    static let browserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static func request(_ url: URL, headers: [String: String] = [:], agent: String = userAgent) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    static func data(_ url: URL, headers: [String: String] = [:], agent: String = userAgent) async throws -> Data {
        let (data, response) = try await session.data(for: request(url, headers: headers, agent: agent))
        guard let http = response as? HTTPURLResponse else {
            throw NetError.invalid
        }
        if http.statusCode == 404 {
            throw NetError.notFound
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetError.status(http.statusCode)
        }
        return data
    }

    static func json<T: Decodable>(_ url: URL, as type: T.Type, headers: [String: String] = [:], snakeCase: Bool = false) async throws -> T {
        let payload = try await data(url, headers: headers)
        let decoder = JSONDecoder()
        if snakeCase {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        return try decoder.decode(T.self, from: payload)
    }

    static func download(_ url: URL, to destination: URL, agent: String = userAgent) async throws {
        let (temporary, response) = try await session.download(for: request(url, agent: agent))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetError.invalid
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    static func components(_ base: String, _ items: [String: String]) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url
    }
}
