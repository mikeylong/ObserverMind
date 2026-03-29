// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ObserverMind",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ObserverMind",
            targets: ["ObserverMind"]
        ),
        .executable(
            name: "observer",
            targets: ["observer"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "ObserverMind",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "observer",
            dependencies: ["ObserverMind"]
        ),
        .testTarget(
            name: "ObserverMindTests",
            dependencies: ["ObserverMind"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
