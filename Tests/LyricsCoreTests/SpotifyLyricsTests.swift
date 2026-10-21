import XCTest
@testable import LyricsCore

private final class SpotifyStub: URLProtocol {
    static let lock = NSLock()
    static var replies: [(Int, String)] = []
    static var requests: [URLRequest] = []
    static func prepare(_ values: [(Int, String)]) {
        lock.lock(); defer { lock.unlock() }
        replies = values; requests = []
    }
    static func snapshot() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let reply = Self.replies.isEmpty ? (500, "{}") : Self.replies.removeFirst()
        Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.0,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SpotifyLyricsTests: XCTestCase {
    private let trackID = "spotify:track:1234567890123456789012"
    private let synced = #"{"lyrics":{"syncType":"LINE_SYNCED","provider":"Musixmatch","lines":[{"startTimeMs":"2000","words":"Second"},{"startTimeMs":"0","words":"♪"},{"startTimeMs":"1000","words":"First"}]}}"#
    private let gist = #"{"files":{"nuances.json":{"content":"[{\"s\":\"GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ\",\"v\":61}]"}}}"#
    private let serverTime = #"{"serverTime":59}"#
    private var token: String {
        "{\"accessToken\":\"test-token\",\"accessTokenExpirationTimestampMs\":\(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000),\"isAnonymous\":false}"
    }
    private func client() -> SpotifyLyricsClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpotifyStub.self]
        return SpotifyLyricsClient(session: URLSession(configuration: configuration))
    }

    func testSyncedLinesSortAndRetainInstrumentalCues() throws {
        let result = try XCTUnwrap(SpotifyLyrics.decode(Data(synced.utf8)))
        XCTAssertEqual(result.lines.map(\.time), [0, 1, 2])
        XCTAssertEqual(result.lines.map(\.text), ["♪", "First", "Second"])
        XCTAssertEqual(result.lines.map(\.id), [0, 1, 2])
        XCTAssertNil(result.plainText)
    }

    func testUnsyncedLyricsStayPlain() throws {
        let body = synced.replacingOccurrences(of: "LINE_SYNCED", with: "UNSYNCED")
        let result = try XCTUnwrap(SpotifyLyrics.decode(Data(body.utf8)))
        XCTAssertTrue(result.lines.isEmpty)
        XCTAssertEqual(result.plainText, "Second\n♪\nFirst")
    }

    func testEmptyMusicCuesAreMissingInsteadOfInstrumentalClaim() throws {
        let body = #"{"lyrics":{"syncType":"LINE_SYNCED","lines":[{"startTimeMs":"0","words":"♪"}]}}"#
        XCTAssertNil(try SpotifyLyrics.decode(Data(body.utf8)))
    }

    func testTOTPUsesRFCVector() throws {
        XCTAssertEqual(try SpotifyLyricsClient.totp(secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", time: 59), "287082")
        XCTAssertThrowsError(try SpotifyLyricsClient.totp(secret: "!", time: 59))
    }

    func testTokenFlowKeepsCookieOffPublicDataRequestsAndCachesLyrics() async throws {
        SpotifyStub.prepare([(200, gist), (200, serverTime), (200, token), (200, synced)])
        let client = client()
        let result = try await client.fetch(trackID: trackID, cookie: "private-session")
        XCTAssertEqual(result?.lines.count, 3)
        _ = try await client.fetch(trackID: trackID, cookie: "private-session")
        let requests = SpotifyStub.snapshot()
        XCTAssertEqual(requests.count, 4)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(requests[2].url?.host, "open.spotify.com")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Cookie"), "sp_dc=private-session")
        XCTAssertNil(requests[3].value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(requests[3].value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    func testNotFoundReturnsNoResultForFallback() async throws {
        SpotifyStub.prepare([(200, gist), (200, serverTime), (200, token), (404, "{}")])
        let result = try await client().fetch(trackID: trackID, cookie: "session")
        XCTAssertNil(result)
    }

    func testUnauthorizedRefreshesTokenOnce() async throws {
        SpotifyStub.prepare([(200, gist), (200, serverTime), (200, token), (401, "{}"),
            (200, serverTime), (200, token), (200, synced)])
        let result = try await client().fetch(trackID: trackID, cookie: "session")
        XCTAssertEqual(result?.lines.count, 3)
        XCTAssertEqual(SpotifyStub.snapshot().count, 7)
    }

    func testAnonymousTokenRejected() async throws {
        SpotifyStub.prepare([(200, gist), (200, serverTime), (200, token.replacingOccurrences(of: "false", with: "true"))])
        do {
            _ = try await client().fetch(trackID: trackID, cookie: "session")
            XCTFail("Expected authentication failure")
        } catch SpotifyLyricsError.authentication {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(SpotifyStub.snapshot().count, 3)
    }

    func testLocalTrackDoesNotMakeNetworkRequests() async throws {
        SpotifyStub.prepare([])
        let result = try await client().fetch(trackID: "spotify:local:artist:album:title", cookie: "session")
        XCTAssertNil(result)
        XCTAssertTrue(SpotifyStub.snapshot().isEmpty)
    }
}
