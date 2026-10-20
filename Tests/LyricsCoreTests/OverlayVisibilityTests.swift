import XCTest
@testable import LyricsCore

final class OverlayVisibilityTests: XCTestCase {
    func testAttachedModeFollowsSpotifyAndPreservesOverlayInteraction() {
        XCTAssertTrue(visible(mode: .spotify, spotify: true))
        XCTAssertTrue(visible(mode: .spotify, interacting: true))
        XCTAssertFalse(visible(mode: .spotify))
    }

    func testIndependentOverlayShowsInOtherApps() {
        XCTAssertTrue(visible(mode: .overlay))
    }

    func testMenuBarModeNeverShowsOverlay() {
        XCTAssertFalse(visible(mode: .menuBar, spotify: true))
        XCTAssertFalse(visible(mode: .menuBar, interacting: true))
    }

    func testManualHideSurvivesFocusChangesInBothWindowModes() {
        XCTAssertFalse(visible(requested: false, mode: .spotify, spotify: true))
        XCTAssertFalse(visible(requested: false, mode: .overlay))
    }

    func testFirstClickRaisesAnObscuredOverlayAndSecondClickCanHideIt() {
        XCTAssertEqual(OverlayVisibility.statusClick(mode: .overlay, visible: true, keyWindow: false, popoverShown: false), .showOverlay)
        XCTAssertEqual(OverlayVisibility.statusClick(mode: .overlay, visible: true, keyWindow: true, popoverShown: false), .hideOverlay)
        XCTAssertEqual(OverlayVisibility.statusClick(mode: .overlay, visible: false, keyWindow: false, popoverShown: false), .showOverlay)
    }

    func testAttachedModeLeftClickAlwaysDetaches() {
        XCTAssertEqual(OverlayVisibility.statusClick(mode: .spotify, visible: true, keyWindow: true, popoverShown: false), .detachSpotify)
        XCTAssertEqual(OverlayVisibility.statusClick(mode: .spotify, visible: false, keyWindow: false, popoverShown: false), .detachSpotify)
    }

    func testMenuBarClickStillTogglesPopover() {
        XCTAssertEqual(OverlayVisibility.statusClick(mode: .menuBar, visible: false, keyWindow: false, popoverShown: false), .openPopover)
        XCTAssertEqual(OverlayVisibility.statusClick(mode: .menuBar, visible: false, keyWindow: false, popoverShown: true), .closePopover)
    }

    func testMigrationPreservesPreviousSpotifyAttachmentWithoutCombiningNewModes() {
        XCTAssertEqual(DisplayMode.restored("overlay", legacyShowWithSpotify: true), .spotify)
        XCTAssertEqual(DisplayMode.restored("overlay", legacyShowWithSpotify: false), .overlay)
        XCTAssertEqual(DisplayMode.restored("menuBar", legacyShowWithSpotify: true), .menuBar)
        XCTAssertEqual(DisplayMode.restored("spotify", legacyShowWithSpotify: false), .spotify)
        XCTAssertEqual(DisplayMode.allCases, [.menuBar, .overlay, .spotify])
    }

    private func visible(requested: Bool = true, mode: DisplayMode, spotify: Bool = false, interacting: Bool = false) -> Bool {
        OverlayVisibility.shouldShow(requested: requested, mode: mode, spotifyFocused: spotify, interactingWithOverlay: interacting)
    }
}
