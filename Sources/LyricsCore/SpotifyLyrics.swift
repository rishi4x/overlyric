import Foundation
import CryptoKit

public struct SpotifyLyrics: Equatable, Sendable {
    public let lines: [LyricLine]
    public let plainText: String?
    public let provider: String?

    public static func decode(_ data: Data) throws -> SpotifyLyrics? {
        struct Response: Decodable {
            struct Body: Decodable {
                struct Line: Decodable { let startTimeMs: String; let words: String }
                let syncType: String
                let lines: [Line]
                let provider: String?
            }
            let lyrics: Body
        }
        let body = try JSONDecoder().decode(Response.self, from: data).lyrics
        guard body.lines.contains(where: {
            let text = $0.words.trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && text != "♪"
        }) else { return nil }
        if body.syncType == "LINE_SYNCED" {
            let timed = body.lines.compactMap { line -> (Double, String)? in
                guard let milliseconds = Double(line.startTimeMs), milliseconds.isFinite, milliseconds >= 0 else { return nil }
                return (milliseconds / 1000, line.words)
            }.enumerated().sorted {
                $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0
            }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.element.0, text: $0.element.element.1) }
            guard !timed.isEmpty else { return nil }
            return SpotifyLyrics(lines: timed, plainText: nil, provider: body.provider)
        }
        return SpotifyLyrics(lines: [], plainText: body.lines.map(\.words).joined(separator: "\n"), provider: body.provider)
    }
}

public enum SpotifyLyricsError: Error {
    case authentication, unavailable(Int), invalidResponse
}

private final class SpotifyRequestDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Authentication is scoped to the original endpoint, including on redirects.
        completionHandler(nil)
    }
}

public actor SpotifyLyricsClient {
    private struct Token: Decodable {
        let accessToken: String
        let accessTokenExpirationTimestampMs: Double
        let isAnonymous: Bool
    }
    private struct Nuance: Decodable { let s: String; let v: Int }
    private var token: Token?
    private var credential: String?
    private var nuance: Nuance?
    private var nuanceDate = Date.distantPast
    private var cache: [String: SpotifyLyrics] = [:]
    private let session: URLSession

    public init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        self.session = session ?? URLSession(configuration: configuration, delegate: SpotifyRequestDelegate(), delegateQueue: nil)
    }

    public func reset() {
        token = nil; credential = nil; cache.removeAll()
    }

    public func validateSession(cookie: String) async throws {
        guard !cookie.isEmpty, !cookie.contains(where: { $0.isNewline || $0 == ";" }) else {
            throw SpotifyLyricsError.authentication
        }
        if credential != cookie { reset(); credential = cookie }
        _ = try await accessToken(cookie: cookie)
    }

    public func fetch(trackID: String, cookie: String, refresh: Bool = false) async throws -> SpotifyLyrics? {
        guard trackID.hasPrefix("spotify:track:") else { return nil }
        let id = String(trackID.dropFirst("spotify:track:".count))
        guard id.count == 22, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        guard !cookie.isEmpty, !cookie.contains(where: { $0.isNewline || $0 == ";" }) else {
            throw SpotifyLyricsError.authentication
        }
        if credential != cookie { reset(); credential = cookie }
        if !refresh, let cached = cache[id] { return cached }
        for attempt in 0..<2 {
            let bearer = try await accessToken(cookie: cookie)
            var request = URLRequest(url: URL(string: "https://spclient.wg.spotify.com/color-lyrics/v2/track/\(id)?format=json&vocalRemoval=false&market=from_token")!)
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            request.setValue("WebPlayer", forHTTPHeaderField: "app-platform")
            request.setValue("https://open.spotify.com", forHTTPHeaderField: "Origin")
            let (data, status) = try await send(request)
            if status == 404 { return nil }
            if status == 401, attempt == 0 { token = nil; continue }
            if status == 401 || status == 403 { throw SpotifyLyricsError.authentication }
            guard status == 200 else { throw SpotifyLyricsError.unavailable(status) }
            let result = try SpotifyLyrics.decode(data)
            if let result {
                if cache.count >= 100 { cache.removeAll() }
                cache[id] = result
            }
            return result
        }
        throw SpotifyLyricsError.authentication
    }

    private func accessToken(cookie: String) async throws -> String {
        if let token, token.accessTokenExpirationTimestampMs / 1000 > Date().timeIntervalSince1970 + 60 {
            return token.accessToken
        }
        // Public protocol parameters only; this request never receives the user's cookie.
        if nuance == nil || Date().timeIntervalSince(nuanceDate) > 3600 {
            struct Gist: Decodable {
                struct File: Decodable { let content: String }
                let files: [String: File]
            }
            let (data, status) = try await send(URLRequest(url: URL(string: "https://api.github.com/gists/22ed9c6ba463899e933427f7de1f0eef")!))
            guard status == 200 else { throw SpotifyLyricsError.unavailable(status) }
            let gist = try JSONDecoder().decode(Gist.self, from: data)
            guard let content = gist.files["nuances.json"]?.content,
                  let latest = try JSONDecoder().decode([Nuance].self, from: Data(content.utf8)).max(by: { $0.v < $1.v }) else {
                throw SpotifyLyricsError.invalidResponse
            }
            nuance = latest; nuanceDate = Date()
        }
        struct ServerTime: Decodable { let serverTime: Double }
        let (timeData, timeStatus) = try await send(URLRequest(url: URL(string: "https://open.spotify.com/api/server-time")!))
        guard timeStatus == 200, let nuance else { throw SpotifyLyricsError.unavailable(timeStatus) }
        let serverTime = try JSONDecoder().decode(ServerTime.self, from: timeData).serverTime
        let code = try Self.totp(secret: nuance.s, time: serverTime)
        var url = URLComponents(string: "https://open.spotify.com/api/token")!
        url.queryItems = [ .init(name: "reason", value: "transport"), .init(name: "productType", value: "web-player"),
            .init(name: "totp", value: code), .init(name: "totpServer", value: code), .init(name: "totpVer", value: String(nuance.v)) ]
        var request = URLRequest(url: url.url!)
        request.setValue("sp_dc=\(cookie)", forHTTPHeaderField: "Cookie")
        let (data, status) = try await send(request)
        guard status == 200 else {
            if status == 401 || status == 403 { self.nuance = nil; throw SpotifyLyricsError.authentication }
            throw SpotifyLyricsError.unavailable(status)
        }
        let result = try JSONDecoder().decode(Token.self, from: data)
        guard !result.isAnonymous, !result.accessToken.isEmpty else { throw SpotifyLyricsError.authentication }
        token = result
        return result.accessToken
    }

    private func send(_ original: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        var request = original
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw SpotifyLyricsError.invalidResponse }
        return (data, response.statusCode)
    }

    static func totp(secret: String, time: Double) throws -> String {
        guard time.isFinite, time >= 0, time < Double(UInt64.max) else { throw SpotifyLyricsError.invalidResponse }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var buffer = 0, bits = 0
        var bytes: [UInt8] = []
        for character in secret.uppercased() where character != "=" {
            guard let value = alphabet.firstIndex(of: character) else { throw SpotifyLyricsError.invalidResponse }
            buffer = ((buffer << 5) | value) & 0xffff
            bits += 5
            if bits >= 8 { bits -= 8; bytes.append(UInt8((buffer >> bits) & 255)) }
        }
        guard !bytes.isEmpty else { throw SpotifyLyricsError.invalidResponse }
        var counter = UInt64(time / 30).bigEndian
        let message = withUnsafeBytes(of: &counter) { Data($0) }
        let hash = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: bytes)))
        let offset = Int(hash.last! & 15)
        let code = (UInt32(hash[offset] & 127) << 24) | (UInt32(hash[offset + 1]) << 16) |
            (UInt32(hash[offset + 2]) << 8) | UInt32(hash[offset + 3])
        return String(format: "%06u", code % 1_000_000)
    }
}
