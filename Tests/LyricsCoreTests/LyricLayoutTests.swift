import XCTest
@testable import LyricsCore

final class LyricLayoutTests: XCTestCase {
    func testDefaultSizePreservesFontPreference() {
        let layout = LyricLayout(width: 390, height: 510)
        XCTAssertEqual(layout.scale, 1)
        XCTAssertEqual(layout.fontSize(base: 30), 30)
    }

    func testWiderPanelsGrowTextWhileAllowingMoreWordsPerLine() {
        let normal = LyricLayout(width: 390, height: 510)
        let wide = LyricLayout(width: 780, height: 510)
        XCTAssertGreaterThan(wide.scale, normal.scale)
        let normalCapacity = (390 - 2 * normal.horizontalPadding) / normal.fontSize(base: 30)
        let wideCapacity = (780 - 2 * wide.horizontalPadding) / wide.fontSize(base: 30)
        XCTAssertGreaterThan(wideCapacity, normalCapacity)
    }

    func testMinimumSizeAndTallNarrowPanelsKeepTextReadable() {
        let small = LyricLayout(width: LyricLayout.minimumWidth, height: LyricLayout.minimumHeight)
        XCTAssertGreaterThanOrEqual(small.fontSize(base: 30), 26.4)
        let short = LyricLayout(width: 340, height: 360)
        let tall = LyricLayout(width: 340, height: 1200)
        XCTAssertLessThan(tall.scale / short.scale, 1.15)
        XCTAssertGreaterThan(tall.scale, short.scale)
    }

    func testScalingIsBoundedAndSmooth() {
        XCTAssertEqual(LyricLayout(width: 0, height: 0).scale, 0.88)
        XCTAssertEqual(LyricLayout(width: 5000, height: 5000).scale, 1.55)
        let first = LyricLayout(width: 500, height: 600)
        let next = LyricLayout(width: 501, height: 600)
        XCTAssertGreaterThan(next.scale, first.scale)
        XCTAssertLessThan(next.scale - first.scale, 0.01)
    }
}
