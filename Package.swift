// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AerialMotion",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "AerialMotion",
            path: "Sources/AerialMotion"
        )
    ]
)
