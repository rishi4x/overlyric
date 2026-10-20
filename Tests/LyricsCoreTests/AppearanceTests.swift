import XCTest
@testable import LyricsCore

final class AppearanceTests: XCTestCase {
    func testDominantColorUsesMajorityRatherThanMixingDifferentColors() throws {
        let pixels: [UInt8] = [240, 30, 30, 255, 242, 31, 30, 255, 20, 40, 240, 255]
        let color = try XCTUnwrap(RGBColor.dominant(in: pixels))
        XCTAssertEqual(color.red, 241.0 / 255, accuracy: 0.001)
        XCTAssertEqual(color.green, 30.5 / 255, accuracy: 0.001)
        XCTAssertEqual(color.blue, 30.0 / 255, accuracy: 0.001)
    }

    func testTransparentPixelsDoNotAffectAccent() throws {
        let color = try XCTUnwrap(RGBColor.dominant(in: [0, 0, 0, 0, 255, 255, 255, 255]))
        XCTAssertEqual(color.red, 1)
        XCTAssertNil(RGBColor.dominant(in: []))
        XCTAssertNil(RGBColor.dominant(in: [0, 0, 0, 0]))
    }

    func testTimingPreferencesRestorePerTrackAndResetIndependently() throws {
        let suite = "OverlyricTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TimingPreferences(defaults: defaults)
        store.setOffset(1.5, for: "spotify:track:first")
        store.setOffset(-2, for: "spotify:track:second")
        let restored = TimingPreferences(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(restored.offset(for: "spotify:track:first"), 1.5)
        XCTAssertEqual(restored.offset(for: "spotify:track:second"), -2)
        XCTAssertEqual(restored.offset(for: "spotify:track:unknown"), 0)
        restored.setOffset(0, for: "spotify:track:first")
        XCTAssertEqual(store.offset(for: "spotify:track:first"), 0)
        XCTAssertEqual(store.offset(for: "spotify:track:second"), -2)
        restored.setOffset(.nan, for: "spotify:track:second")
        XCTAssertEqual(store.offset(for: "spotify:track:second"), -2)
    }
}
