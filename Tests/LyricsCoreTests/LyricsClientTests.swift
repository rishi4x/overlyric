import XCTest
@testable import LyricsCore

private final class StubLyricsProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var body = ""
        var retryAfter: String?
        var error: URLError?
    }
    static let lock = NSLock()
    static var replies: [Reply] = []
    static var requests = 0

    static func prepare(_ values: [Reply]) {
        lock.lock(); defer { lock.unlock() }
        replies = values; requests = 0
    }
    static func requestCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return requests
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        let reply = Self.replies.isEmpty ? Reply(status: 500) : Self.replies.removeFirst()
        Self.lock.unlock()
        if let error = reply.error { client?.urlProtocol(self, didFailWithError: error); return }
        let headers = reply.retryAfter.map { ["Retry-After": $0] } ?? [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor Delays {
    var values: [Double] = []
    func append(_ value: Double) { values.append(value) }
}

final class LyricsClientTests: XCTestCase {
    private let track = Track(id: "spotify:track:test", title: "Song", artist: "Artist", album: "Album", duration: 180)
    private let fixture = #"{"id":1,"trackName":"Song","artistName":"Artist","albumName":"Album","duration":180,"instrumental":false,"plainLyrics":"Words","syncedLyrics":"[00:01]Words"}"#

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubLyricsProtocol.self]
        return URLSession(configuration: config)
    }

    func testTemporaryServerErrorsRecoverAndCacheSuccess() async throws {
        StubLyricsProtocol.prepare([.init(status: 503), .init(status: 502), .init(body: fixture)])
        let delays = Delays()
        let client = LyricsClient(session: session(), wait: { await delays.append($0) })
        let result = try await client.fetch(track)
        XCTAssertEqual(result.id, 1)
        _ = try await client.fetch(track)
        XCTAssertEqual(StubLyricsProtocol.requestCount(), 3)
        let waits = await delays.values
        XCTAssertEqual(waits, [1, 2])
    }

    func testSearchRetriesAndHonorsRetryAfter() async throws {
        StubLyricsProtocol.prepare([.init(status: 429, retryAfter: "3"), .init(body: "[\(fixture)]")])
        let delays = Delays()
        let client = LyricsClient(session: session(), wait: { await delays.append($0) })
        let result = try await client.search(track)
        XCTAssertEqual(result.map(\.id), [1])
        let waits = await delays.values
        XCTAssertEqual(waits, [3])
    }

    func testNotFoundGoesStraightToFallbackWithoutRetry() async {
        StubLyricsProtocol.prepare([.init(status: 404)])
        let client = LyricsClient(session: session(), wait: { _ in XCTFail("404 must not retry") })
        do { _ = try await client.fetch(track); XCTFail("Expected missing lyrics") }
        catch LyricsError.notFound {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(StubLyricsProtocol.requestCount(), 1)
    }

    func testRetryLimit() async {
        StubLyricsProtocol.prepare(Array(repeating: .init(status: 503), count: 5))
        let client = LyricsClient(session: session(), wait: { _ in })
        do { _ = try await client.fetch(track); XCTFail("Expected server error") }
        catch LyricsError.server(503) {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(StubLyricsProtocol.requestCount(), 4)
    }

    func testNetworkTimeoutRecovers() async throws {
        StubLyricsProtocol.prepare([.init(error: URLError(.timedOut)), .init(body: fixture)])
        let client = LyricsClient(session: session(), wait: { _ in })
        _ = try await client.fetch(track)
        XCTAssertEqual(StubLyricsProtocol.requestCount(), 2)
    }

    func testCancellationDuringBackoffStopsRetry() async {
        StubLyricsProtocol.prepare([.init(status: 503), .init(body: fixture)])
        let enteredWait = expectation(description: "Retry backoff entered")
        let client = LyricsClient(session: session(), wait: { _ in
            enteredWait.fulfill()
            try await Task.sleep(for: .seconds(60))
        })
        let task = Task { try await client.fetch(track) }
        await fulfillment(of: [enteredWait], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(StubLyricsProtocol.requestCount(), 1)
    }

    func testLookupKeepsInstrumentalMarkersAcrossDurationMismatchAndCachesResult() async throws {
        let instrumental = #"{"id":2,"trackName":"Song","artistName":"ARTIST","albumName":"Album","duration":192,"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#
        StubLyricsProtocol.prepare([.init(status: 404), .init(body: "[\(instrumental)]")])
        let client = LyricsClient(session: session(), wait: { _ in })
        guard case .instrumental = try await client.lookup(track) else { return XCTFail("Expected explicit instrumental marker") }
        guard case .instrumental = try await client.lookup(track) else { return XCTFail("Expected cached marker") }
        XCTAssertEqual(StubLyricsProtocol.requestCount(), 2)
    }

    func testMissingLyricsAreOrdinaryResultAndCanBeRechecked() async throws {
        StubLyricsProtocol.prepare([.init(status: 404), .init(body: "[]"), .init(body: fixture)])
        let client = LyricsClient(session: session(), wait: { _ in })
        guard case .missing = try await client.lookup(track) else { return XCTFail("Expected missing result, not error") }
        guard case .record = try await client.lookup(track, refresh: true) else { return XCTFail("Rechecking should bypass cache") }
        XCTAssertEqual(StubLyricsProtocol.requestCount(), 3)
    }

    func testSearchCanRecoverWhenExactLookupReturns503() async throws {
        let instrumental = #"{"id":2,"trackName":"Song","artistName":"Artist","albumName":"Album","duration":180,"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#
        StubLyricsProtocol.prepare(Array(repeating: .init(status: 503), count: 4) + [.init(body: "[\(instrumental)]")])
        let client = LyricsClient(session: session(), wait: { _ in })
        guard case .instrumental = try await client.lookup(track) else { return XCTFail("Search should recover the instrumental marker") }
        XCTAssertEqual(StubLyricsProtocol.requestCount(), 5)
    }

    func testConflictingMarkersAndOtherAlbumsDoNotAutomaticallyDeclareInstrumental() throws {
        let marked = try JSONDecoder().decode(LyricsRecord.self, from: Data(#"{"id":2,"trackName":"Song","artistName":"Artist","albumName":"Other album","duration":180,"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#.utf8))
        guard case .candidates = LyricsLookup.resolve([marked], for: track) else { return XCTFail("Different album requires user choice") }
        let sameAlbum = try JSONDecoder().decode(LyricsRecord.self, from: Data(#"{"id":3,"trackName":"Song","artistName":"Artist","albumName":"Album","duration":180,"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#.utf8))
        let withLyrics = try JSONDecoder().decode(LyricsRecord.self, from: Data(fixture.utf8))
        guard case .candidates = LyricsLookup.resolve([sameAlbum, withLyrics], for: track) else { return XCTFail("Conflicting records require user choice") }
    }

    func testEmptyTextDoesNotCountAsAvailableLyrics() throws {
        let record = try JSONDecoder().decode(LyricsRecord.self, from: Data(#"{"id":2,"trackName":"Song","artistName":"Artist","albumName":"Album","duration":180,"instrumental":false,"plainLyrics":"  ","syncedLyrics":"[00:00] "}"#.utf8))
        XCTAssertFalse(record.hasLyrics)
    }

    func testServiceFailureIsNeverCachedAsMissingOrInstrumental() async throws {
        StubLyricsProtocol.prepare(Array(repeating: .init(status: 503), count: 8))
        let client = LyricsClient(session: session(), wait: { _ in })
        do { _ = try await client.lookup(track); XCTFail("Service failure must remain an error") }
        catch LyricsError.server(503) {} catch { XCTFail("Unexpected error: \(error)") }
        StubLyricsProtocol.prepare([.init(status: 404), .init(body: "[]")])
        guard case .missing = try await client.lookup(track) else { return XCTFail("Must make a fresh lookup after service failure") }
        XCTAssertEqual(StubLyricsProtocol.requestCount(), 2)
    }

    func testManualSearchAllowsDifferentTitlesWhileAutomaticMatchingStaysStrict() async throws {
        let alternate = fixture.replacingOccurrences(of: "\"trackName\":\"Song\"", with: "\"trackName\":\"Alternate Song\"")
        StubLyricsProtocol.prepare([.init(body: "[\(alternate)]"), .init(body: "[\(alternate)]")])
        let client = LyricsClient(session: session(), wait: { _ in })
        let manual = try await client.search(title: "Alternate", artist: "")
        XCTAssertEqual(manual.first?.trackName, "Alternate Song")
        let automatic = try await client.search(track)
        XCTAssertTrue(automatic.isEmpty)
    }
}
