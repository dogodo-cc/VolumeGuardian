// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VolumeGuardian",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "volume-guardian",
            targets: ["VolumeGuardian"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VolumeGuardian"
        )
    ]
)