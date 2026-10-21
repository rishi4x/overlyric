import Foundation

public struct LoginAtLogin {
    private static let label = "com.rishi.overlyric.login"
    private let file: URL
    private let application: URL

    public init(file: URL? = nil, application: URL = Bundle.main.bundleURL) {
        self.file = file ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
        self.application = application
    }

    public var isEnabled: Bool {
        guard let data = try? Data(contentsOf: file),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
        return value["Label"] as? String == Self.label && value["RunAtLoad"] as? Bool == true
    }

    public func setEnabled(_ enabled: Bool) throws {
        let manager = FileManager.default
        if enabled {
            let plist: [String: Any] = [
                "Label": Self.label,
                "ProgramArguments": ["/usr/bin/open", "-g", "-a", application.path],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua",
                "AssociatedBundleIdentifiers": ["com.rishi.overlyric"]
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } else if manager.fileExists(atPath: file.path) {
            try manager.removeItem(at: file)
        }
    }
}
