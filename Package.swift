// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Lee-SystemPulse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "lee-system-pulse",
            targets: ["LeeSystemPulse"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "LeeSystemPulse",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "LeeSystemPulseTests",
            dependencies: ["LeeSystemPulse"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
