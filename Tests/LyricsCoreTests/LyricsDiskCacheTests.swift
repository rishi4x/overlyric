import XCTest
@testable import LyricsCore

private actor LookupGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { await withCheckedContinuation { waiters.append($0) } }
    func release() { waiters.forEach { $0.resume() }; waiters.removeAll() }
}

final class LyricsDiskCacheTests: XCTestCase {
    private let track = Track(id: "spotify:track:cache-test", title: "Song", artist: "Artist", album: "Album", duration: 100)
    private func record(_ id: Int = 1) -> LyricsRecord {
        LyricsRecord(id: id, trackName: "Song", artistName: "Artist", albumName: "Album", duration: 100,
            instrumental: false, plainLyrics: nil, syncedLyrics: "[00:10]Words", source: .netease)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testDiskRoundTripAcrossInstancesAndInvalidation() throws {
        let folder = try directory()
        let now = Date()
        let cache = LyricsDiskCache(directory: folder, lifetime: 60)
        cache.save(LyricsResolution(source: .netease, lookup: .record(record())), for: track, now: now)
        let restored = LyricsDiskCache(directory: folder, lifetime: 60).load(track, now: now.addingTimeInterval(30))
        XCTAssertEqual(restored?.source, .netease)
        XCTAssertNil(cache.load(track, now: now.addingTimeInterval(61)))
        let changed = Track(id: track.id, title: "Different song", artist: track.artist, album: track.album, duration: track.duration)
        XCTAssertNil(cache.load(changed, now: now))
    }

    func testMissingAndCorruptEntriesAreIgnored() throws {
        let folder = try directory()
        let cache = LyricsDiskCache(directory: folder)
        cache.save(LyricsResolution(source: .netease, lookup: .missing), for: track)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        cache.save(LyricsResolution(source: .netease, lookup: .record(record())), for: track)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        try Data("corrupt".utf8).write(to: file)
        XCTAssertNil(cache.load(track))
    }

    func testEntryLimitEvictsOldest() throws {
        let cache = LyricsDiskCache(directory: try directory(), maxEntries: 1)
        cache.save(LyricsResolution(source: .netease, lookup: .record(record())), for: track)
        let other = Track(id: "other", title: "Song", artist: "Artist", album: "Album", duration: 100)
        cache.save(LyricsResolution(source: .netease, lookup: .record(record(2))), for: other)
        XCTAssertNil(cache.load(track))
        XCTAssertNotNil(cache.load(other))
    }

    func testByteLimitRejectsOversizedEntry() throws {
        let cache = LyricsDiskCache(directory: try directory(), maxBytes: 10)
        cache.save(LyricsResolution(source: .netease, lookup: .record(record())), for: track)
        XCTAssertNil(cache.load(track))
    }

    func testSavedManualChoiceSkipsNetworkAndReloadBypassesCache() async throws {
        let cache = LyricsDiskCache(directory: try directory())
        let resolver = LyricsResolver(primary: { _, _ in .missing }, fallback: { _, _ in .missing }, diskCache: cache)
        await resolver.remember(record(42), for: track)
        let nextInstance = LyricsResolver(primary: { _, refresh in
            XCTAssertTrue(refresh, "Cached song should make no network calls"); return .missing
        }, fallback: { _, refresh in
            XCTAssertTrue(refresh); return .missing
        }, diskCache: cache)
        let saved = try await nextInstance.lookup(track)
        guard case .record(let restored) = saved.lookup else { return XCTFail("Expected saved selection") }
        XCTAssertEqual(restored.id, 42)
        let reloaded = try await nextInstance.lookup(track, refresh: true)
        guard case .missing = reloaded.lookup else { return XCTFail("Reload must bypass saved lyrics") }
    }

    func testBothProvidersBeginBeforeEitherCompletes() async throws {
        let started = expectation(description: "Both requests started")
        started.expectedFulfillmentCount = 2
        let gate = LookupGate()
        let record = record()
        let resolver = LyricsResolver(primary: { _, _ in
            started.fulfill(); await gate.wait(); return .missing
        }, fallback: { _, _ in
            started.fulfill(); await gate.wait(); return .record(record)
        })
        let track = track
        let task = Task { try await resolver.lookup(track) }
        await fulfillment(of: [started], timeout: 2)
        await gate.release()
        let result = try await task.value
        XCTAssertEqual(result.source, .netease)
    }
}
