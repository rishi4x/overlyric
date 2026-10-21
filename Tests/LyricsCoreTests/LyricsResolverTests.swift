import XCTest
@testable import LyricsCore

private actor ProviderCalls {
    var fallback = 0
    func called() { fallback += 1 }
}

final class LyricsResolverTests: XCTestCase {
    private let track = Track(id: "test", title: "Song", artist: "Artist", album: "Album", duration: 100)
    private func record(source: LyricsSource = .lrclib) -> LyricsRecord {
        LyricsRecord(id: 1, trackName: "Song", artistName: "Artist", albumName: "Album", duration: 100,
            instrumental: false, plainLyrics: nil, syncedLyrics: "[00:10]Words", source: source)
    }

    func testPrimaryLyricsWinWhileBothProvidersStart() async throws {
        let record = record()
        let calls = ProviderCalls()
        let resolver = LyricsResolver(primary: { _, _ in .record(record) }, fallback: { _, _ in
            await calls.called(); return .missing
        })
        let result = try await resolver.lookup(track)
        XCTAssertEqual(result.source, .lrclib)
        let count = await calls.fallback
        XCTAssertEqual(count, 1)
    }

    func testMissingPrimaryUsesNetEase() async throws {
        let record = record(source: .netease)
        let resolver = LyricsResolver(primary: { _, _ in .missing }, fallback: { _, refresh in
            XCTAssertTrue(refresh); return .record(record)
        })
        let result = try await resolver.lookup(track, refresh: true)
        XCTAssertEqual(result.source, .netease)
    }

    func testPrimaryServiceFailureCanRecoverWithFallback() async throws {
        let record = record(source: .netease)
        let resolver = LyricsResolver(primary: { _, _ in throw LyricsError.server(503) }, fallback: { _, _ in .record(record) })
        let result = try await resolver.lookup(track)
        XCTAssertEqual(result.source, .netease)
    }

    func testInstrumentalPrimaryWinsConcurrentFallback() async throws {
        let resolver = LyricsResolver(primary: { _, _ in .instrumental }, fallback: { _, _ in
            return .missing
        })
        let result = try await resolver.lookup(track)
        XCTAssertEqual(result.source, .lrclib)
    }

    func testMissingFallbackDoesNotHidePrimaryOutage() async throws {
        let resolver = LyricsResolver(primary: { _, _ in throw LyricsError.server(503) }, fallback: { _, _ in .missing })
        do { _ = try await resolver.lookup(track); XCTFail("Expected outage") }
        catch LyricsError.server(503) {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testAlreadyCancelledLookupDoesNotStartProviders() async throws {
        let resolver = LyricsResolver(primary: { _, _ in
            XCTFail("Cancelled task must not start primary"); return .missing
        }, fallback: { _, _ in
            XCTFail("Cancelled task must not start fallback"); return .missing
        })
        let track = track
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await resolver.lookup(track)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCreditFilterPreservesRealLinesAndTheirTiming() {
        let raw = "[00:00.000] 作词 : Writer\n[00:01.000] 作曲：Composer\n[00:02.000] 制作人 : Producer\n[00:03.000] Produced by: Someone\n[00:18.097]First lyric\n[00:21.695]The producer told me: keep going\n[00:24.000]Words without a colon"
        let lines = LRC.parse(NetEaseLyricsClient.removingCredits(raw))
        XCTAssertEqual(lines.map(\.time), [18.097, 21.695, 24])
        XCTAssertEqual(lines[1].text, "The producer told me: keep going")
    }

    func testCreditOnlyResponsesBecomeEmpty() {
        XCTAssertEqual(NetEaseLyricsClient.removingCredits("[00:00] 作詞：Writer\nComposer: Someone"), "")
        XCTAssertEqual(NetEaseLyricsClient.removingCredits("[00:00]Producer of my dreams"), "[00:00]Producer of my dreams")
    }
}
