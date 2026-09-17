// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "prBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "PRBarCore", targets: ["PRBarCore"]),
        .executable(name: "prBar", targets: ["PRBar"]),
        // Not `prbar`: APFS is case-insensitive, so it would collide with `prBar`.
        .executable(name: "prbar-cli", targets: ["PRBarCLI"]),
    ],
    targets: [
        .target(
            name: "PRBarCore",
            path: "Sources/PRBarCore"
        ),
        .executableTarget(
            name: "PRBar",
            dependencies: ["PRBarCore"],
            path: "Sources/PRBar"
        ),
        .executableTarget(
            name: "PRBarCLI",
            dependencies: ["PRBarCore"],
            path: "Sources/PRBarCLI"
        ),
        .testTarget(
            name: "PRBarTests",
            dependencies: ["PRBarCore"],
            path: "Tests/PRBarTests"
        ),
    ]
)
