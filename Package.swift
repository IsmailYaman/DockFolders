// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "DockFolders",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "DockFolders",
            path: "Sources/DockFolders",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
