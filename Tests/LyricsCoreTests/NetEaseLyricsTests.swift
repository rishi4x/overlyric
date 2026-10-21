import XCTest
@testable import LyricsCore

private final class NetEaseStub: URLProtocol {
    static let lock = NSLock()
    static var replies: [(Int, String)] = []
    static var urls: [URL] = []
    static func prepare(_ values: [(Int, String)]) {
        lock.lock(); defer { lock.unlock() }
        replies = values; urls = []
    }
    static func requests() -> [URL] {
        lock.lock(); defer { lock.unlock() }
        return urls
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.urls.append(request.url!)
        let reply = Self.replies.isEmpty ? (500, "{}") : Self.replies.removeFirst()
        Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.0,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class NetEaseLyricsTests: XCTestCase {
    private let track = Track(id: "spotify:track:test", title: "Song", artist: "Artist", album: "Album", duration: 137)
    private let search = #"{"code":200,"result":{"songs":[{"id":123,"name":"Song","artists":[{"name":"Artist"}],"album":{"name":"Album"},"duration":137000}]}}"#
    private let lyrics = #"{"code":200,"lrc":{"lyric":"[00:18.097]First line\n[00:21.234]Next line"}}"#
    private func client() -> NetEaseLyricsClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NetEaseStub.self]
        return NetEaseLyricsClient(session: URLSession(configuration: config), wait: { _ in })
    }

    func testExactRecordingAndTimedLyricsUseOnlyNetEase() async throws {
        NetEaseStub.prepare([(200, search), (200, lyrics)])
        let result = try await client().lookup(track)
        guard case .record(let record) = result else { return XCTFail("Expected exact recording") }
        XCTAssertEqual(record.duration, 137)
        XCTAssertEqual(LRC.parse(record.syncedLyrics ?? "").map(\.time), [18.097, 21.234])
        XCTAssertTrue(NetEaseStub.requests().allSatisfy { $0.host == "music.163.com" })
    }

    func testWrongArtistAndDifferentDurationAreExcluded() async throws {
        let bad = search.replacingOccurrences(of: "Artist", with: "Cover artist")
        NetEaseStub.prepare([(200, bad)])
        let first = try await client().lookup(track)
        guard case .missing = first else { return XCTFail("Wrong artist matched") }
        NetEaseStub.prepare([(200, search.replacingOccurrences(of: "137000", with: "220000"))])
        let second = try await client().lookup(track)
        guard case .missing = second else { return XCTFail("Different duration matched") }
        XCTAssertEqual(NetEaseStub.requests().count, 1)
    }

    func testBlockedSearchIsErrorInsteadOfMissingOrInstrumental() async throws {
        NetEaseStub.prepare([(200, #"{"code":-462}"#)])
        do {
            _ = try await client().lookup(track)
            XCTFail("Expected service error")
        } catch NetEaseError.unavailable(-462) {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testEmptyLyricsAreNotInstrumental() async throws {
        NetEaseStub.prepare([(200, search), (200, #"{"code":200,"lrc":{"lyric":""}}"#)])
        let result = try await client().lookup(track)
        guard case .missing = result else { return XCTFail("Expected missing, not instrumental") }
    }

    func testExplicitInstrumentalMarkerRetained() async throws {
        NetEaseStub.prepare([(200, search), (200, #"{"code":200,"nolyric":true}"#)])
        let result = try await client().lookup(track)
        guard case .record(let record) = result else { return XCTFail("Expected record") }
        XCTAssertTrue(record.instrumental)
    }

    func testServerFailureRetriesAndRefreshBypassesLyricsCache() async throws {
        NetEaseStub.prepare([(503, "{}"), (200, search), (200, lyrics), (200, search), (200, search), (200, lyrics)])
        let client = client()
        _ = try await client.lookup(track)
        _ = try await client.lookup(track)
        XCTAssertEqual(NetEaseStub.requests().count, 4)
        _ = try await client.lookup(track, refresh: true)
        XCTAssertEqual(NetEaseStub.requests().count, 6)
    }

    func testSearchWithNoResultsReturnsMissing() async throws {
        NetEaseStub.prepare([(200, #"{"code":200,"result":{"songCount":0}}"#)])
        let result = try await client().lookup(track)
        guard case .missing = result else { return XCTFail("Expected missing") }
    }
}
