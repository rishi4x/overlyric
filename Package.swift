// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Overlyric",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Overlyric", targets: ["Overlyric"])],
    targets: [
        .target(name: "LyricsCore"),
        .executableTarget(name: "Overlyric", dependencies: ["LyricsCore"]),
        .testTarget(name: "LyricsCoreTests", dependencies: ["LyricsCore"])
    ],
    swiftLanguageModes: [.v5]
)
