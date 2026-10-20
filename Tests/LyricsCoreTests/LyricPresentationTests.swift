import XCTest
@testable import LyricsCore

final class LyricPresentationTests: XCTestCase {
    func testCurrentLineStaysSharpAndNextLineHasOnlyASlightBlur() {
        XCTAssertEqual(LyricEmphasis.at(5, activeIndex: 5).blur, 0)
        XCTAssertGreaterThan(LyricEmphasis.at(6, activeIndex: 5).blur, 0)
        XCTAssertLessThan(LyricEmphasis.at(6, activeIndex: 5).blur, LyricEmphasis.at(7, activeIndex: 5).blur)
        XCTAssertLessThan(LyricEmphasis.at(5, activeIndex: 5).opacity, 1)
        XCTAssertGreaterThan(LyricEmphasis.at(5, activeIndex: 5).opacity, LyricEmphasis.at(6, activeIndex: 5).opacity)
        XCTAssertLessThan(LyricEmphasis.at(4, activeIndex: 5).blur, LyricEmphasis.at(3, activeIndex: 5).blur)
        XCTAssertGreaterThan(LyricEmphasis.at(4, activeIndex: 5).opacity, LyricEmphasis.at(3, activeIndex: 5).opacity)
        XCTAssertLessThan(LyricEmphasis.at(7, activeIndex: 5).blur, LyricEmphasis.at(8, activeIndex: 5).blur)
        XCTAssertGreaterThan(LyricEmphasis.at(7, activeIndex: 5).opacity, LyricEmphasis.at(8, activeIndex: 5).opacity)
    }

    func testBeforeFirstCueIsReadableWithoutAnActiveHighlightAndBlurIsBounded() {
        let first = LyricEmphasis.at(0, activeIndex: nil)
        XCTAssertEqual(first.blur, 0)
        XCTAssertLessThan(first.opacity, 1)
        XCTAssertLessThanOrEqual(LyricEmphasis.at(100, activeIndex: 0).blur, 4.8)
        XCTAssertGreaterThan(LyricEmphasis.at(0, activeIndex: 100).opacity, 0)
    }

    func testScrollHandleMapsContentProgressToLimitedTrack() {
        let metrics = LyricScrollMetrics(offset: 750, contentHeight: 2000, viewportHeight: 500)
        XCTAssertEqual(metrics.maximumOffset, 1500)
        XCTAssertEqual(metrics.progress, 0.5)
        XCTAssertEqual(metrics.thumbHeight(in: 300), 75)
        XCTAssertEqual(metrics.offset(at: 0.5), 750)
        XCTAssertEqual(metrics.offset(at: -1), 0)
        XCTAssertEqual(metrics.offset(at: 2), 1500)
    }

    func testHandleClampsOverscrollAndFitsShortTracks() {
        XCTAssertEqual(LyricScrollMetrics(offset: -20, contentHeight: 1000, viewportHeight: 500).progress, 0)
        XCTAssertEqual(LyricScrollMetrics(offset: 600, contentHeight: 1000, viewportHeight: 500).progress, 1)
        let long = LyricScrollMetrics(offset: 0, contentHeight: 10000, viewportHeight: 500)
        XCTAssertEqual(long.thumbHeight(in: 200), 28)
        XCTAssertEqual(long.thumbHeight(in: 16), 16)
        let empty = LyricScrollMetrics()
        XCTAssertEqual(empty.progress, 0)
        XCTAssertEqual(empty.maximumOffset, 0)
    }
}
