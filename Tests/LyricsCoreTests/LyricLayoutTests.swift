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

    func testBlurKeepsTheSameStrengthRelativeToFontSize() {
        let normal = LyricLayout(width: 390, height: 510)
        let large = LyricLayout(width: 780, height: 1000)
        XCTAssertEqual(normal.blurRadius(base: 4, fontSize: 30), 4)
        XCTAssertGreaterThan(large.blurRadius(base: 4, fontSize: 30), 4)
        for layout in [normal, large] {
            for font in [21.0, 30.0, 45.0] {
                XCTAssertEqual(layout.blurRadius(base: 4, fontSize: font) / layout.fontSize(base: font), 4.0 / 30, accuracy: 0.0001)
                XCTAssertEqual(layout.blurRadius(base: 0, fontSize: font), 0)
            }
        }
    }

    func testOnlyGapsFarFromCurrentLineBecomeCompact() {
        let layout = LyricLayout(width: 390, height: 510)
        for index in [3, 4, 5, 6] {
            XCTAssertEqual(layout.rowSpacing(after: index, activeIndex: 5), layout.rowSpacing)
        }
        for index in [0, 1, 2, 7, 8, 9] {
            XCTAssertLessThan(layout.rowSpacing(after: index, activeIndex: 5), layout.rowSpacing)
        }
        XCTAssertEqual(layout.rowSpacing(after: 3, activeIndex: nil), layout.rowSpacing)
        let large = LyricLayout(width: 780, height: 1000)
        XCTAssertEqual(large.rowSpacing(after: 2, activeIndex: 5) / large.rowSpacing, 0.6, accuracy: 0.0001)
    }
}
