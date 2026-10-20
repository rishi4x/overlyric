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

    func testDarkPurpleShadowsDoNotOverrideWarmCoverColors() throws {
        // Representative color families from the reported warm portrait cover.
        let families: [([UInt8], Int)] = [([8, 6, 8, 255], 915), ([21, 19, 19, 255], 430),
                                        ([87, 53, 42, 255], 263), ([55, 40, 36, 255], 188)]
        var pixels: [UInt8] = []
        for (pixel, count) in families {
            for _ in 0..<count { pixels.append(contentsOf: pixel) }
        }
        let color = try XCTUnwrap(RGBColor.dominant(in: pixels))
        XCTAssertEqual(color.red, 87.0 / 255, accuracy: 0.001)
        XCTAssertGreaterThan(color.red, color.green)
        XCTAssertGreaterThan(color.green, color.blue)
    }

    func testNearBlackArtworkRemainsNeutralWhenNoVisibleColorsExist() throws {
        let color = try XCTUnwrap(RGBColor.dominant(in: [8, 6, 8, 255, 9, 6, 9, 255]))
        XCTAssertEqual(color.red, color.green)
        XCTAssertEqual(color.green, color.blue)
    }

    func testAmbienceOmitsNeutralsAndPreservesDistinctBoldHues() {
        let families: [([UInt8], Int)] = [([250, 250, 250, 255], 100), ([8, 6, 8, 255], 100),
                                        ([220, 25, 25, 255], 10), ([25, 25, 220, 255], 8),
                                        ([25, 220, 25, 255], 6)]
        var pixels: [UInt8] = []
        for (pixel, count) in families {
            for _ in 0..<count { pixels.append(contentsOf: pixel) }
        }
        let palette = RGBColor.ambiencePalette(in: pixels)
        XCTAssertEqual(palette.count, 3)
        XCTAssertGreaterThan(palette[0].red, palette[0].blue)
        XCTAssertTrue(palette.contains { $0.blue > $0.red && $0.blue > $0.green })
        XCTAssertTrue(palette.contains { $0.green > $0.red && $0.green > $0.blue })
        XCTAssertEqual(RGBColor.ambiencePalette(in: pixels, limit: 1).count, 1)
        XCTAssertTrue(RGBColor.ambiencePalette(in: pixels, limit: 0).isEmpty)
    }

    func testAmbienceDoesNotInventColorsForNeutralOrTransparentCovers() {
        XCTAssertTrue(RGBColor.ambiencePalette(in: [255, 255, 255, 255, 110, 110, 110, 255, 8, 6, 8, 255]).isEmpty)
        XCTAssertTrue(RGBColor.ambiencePalette(in: [230, 10, 10, 0]).isEmpty)
        XCTAssertTrue(RGBColor.ambiencePalette(in: []).isEmpty)
    }

    func testAmbienceMergesSimilarHuesAcrossTheRedHueBoundary() {
        let palette = RGBColor.ambiencePalette(in: [240, 20, 30, 255, 240, 30, 20, 255])
        XCTAssertEqual(palette.count, 1)
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
