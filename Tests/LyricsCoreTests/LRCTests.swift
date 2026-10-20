import XCTest
@testable import LyricsCore

final class LRCTests: XCTestCase {
    func testMultipleTimestampsAndMetadata() {
        let lines = LRC.parse("[ar:Artist]\n[00:14.25][01:02.500]Chorus\n[00:01.2]First\n[00:30.00]\ninvalid")
        XCTAssertEqual(lines.map(\.time), [1.2, 14.25, 30, 62.5])
        XCTAssertEqual(lines.map(\.text), ["First", "Chorus", "", "Chorus"])
        XCTAssertEqual(Set(lines.map(\.id)).count, 4)
    }

    func testOffsetAndInvalidSeconds() {
        let lines = LRC.parse("[offset:-500]\n[00:00.20]Start\n[00:02.00]Next\n[00:99]Bad")
        XCTAssertEqual(lines.map(\.time), [0, 1.5])
    }

    func testActiveLineBoundariesAndSeekBackwards() {
        let lines = LRC.parse("[00:05]First\n[00:10]Second\n[00:10]Duplicate\n[00:20]")
        XCTAssertNil(LRC.activeIndex(in: lines, at: 4.99))
        XCTAssertEqual(LRC.activeIndex(in: lines, at: 5), 0)
        XCTAssertEqual(LRC.activeIndex(in: lines, at: 10), 2)
        XCTAssertEqual(LRC.activeIndex(in: lines, at: 100), 3)
        XCTAssertEqual(LRC.activeIndex(in: lines, at: 7), 0)
        XCTAssertNil(LRC.activeIndex(in: [], at: 5))
    }
}
