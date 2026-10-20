import XCTest
@testable import LyricsCore

final class RecordingPreferencesTests: XCTestCase {
    private func record(_ id: Int) throws -> LyricsRecord {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id, "trackName": "Song", "artistName": "Artist", "albumName": "Album",
            "duration": 180, "instrumental": false, "syncedLyrics": "[00:01]Words"
        ])
        return try JSONDecoder().decode(LyricsRecord.self, from: data)
    }

    func testFirstResultIsAutomaticDefaultAndMissingPreferenceFallsBack() throws {
        let suite = "RecordingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecordingPreferences(defaults: defaults)
        let records = try [record(2), record(1)]
        XCTAssertEqual(store.preferredRecording(in: records, for: "song")?.id, 2)
        XCTAssertFalse(store.isNoticeDismissed(for: "song"))
        store.remember(99, for: "song")
        XCTAssertEqual(store.preferredRecording(in: records, for: "song")?.id, 2)
        XCTAssertNil(store.preferredRecording(in: [], for: "song"))
    }

    func testChoiceAndDismissalPersistPerSongIndependently() throws {
        let suite = "RecordingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecordingPreferences(defaults: defaults)
        let records = try [record(1), record(2)]
        store.remember(2, for: "first")
        XCTAssertFalse(store.isNoticeDismissed(for: "first"))
        store.dismissNotice(for: "first")
        store.remember(1, for: "second")
        let restored = RecordingPreferences(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(restored.preferredRecording(in: records, for: "first")?.id, 2)
        XCTAssertTrue(restored.isNoticeDismissed(for: "first"))
        XCTAssertFalse(restored.isNoticeDismissed(for: "second"))
        store.remember(1, for: "first")
        XCTAssertTrue(restored.isNoticeDismissed(for: "first"))
        XCTAssertEqual(restored.preferredRecording(in: records, for: "first")?.id, 1)
    }
}
