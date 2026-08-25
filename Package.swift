// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HyperTyper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HyperTyper",
            path: "Sources/HyperTyper"
        )
    ]
)
