// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DevPilotMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DevPilotMenuBar", targets: ["DevPilotMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "DevPilotMenuBar",
            path: "Sources"
        )
    ]
)
