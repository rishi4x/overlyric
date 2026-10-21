import XCTest
@testable import LyricsCore

final class LoginAtLoginTests: XCTestCase {
    func testDefaultsOffAndTogglePersistsWithoutLaunchingAnything() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("LaunchAgents/com.rishi.overlyric.login.plist")
        let app = URL(fileURLWithPath: "/Applications/Overlyric.app")
        let item = LoginAtLogin(file: file, application: app)
        XCTAssertFalse(item.isEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        try item.setEnabled(true)
        XCTAssertTrue(LoginAtLogin(file: file, application: app).isEnabled)
        let data = try Data(contentsOf: file)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/usr/bin/open", "-g", "-a", app.path])
        XCTAssertNil(plist["KeepAlive"])
        try item.setEnabled(false)
        XCTAssertFalse(item.isEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try item.setEnabled(false)
    }
}
