// swift-tools-version: 6.1.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Simulo",
    products: [
        .library(
            name: "Simulo",
            targets: ["Simulo"],
        )
    ],
    targets: [
        .target(
            name: "Simulo",
            swiftSettings: [
                .enableExperimentalFeature("Extern")
            ]
        ),
        .testTarget(
            name: "SimuloTests",
            dependencies: ["Simulo"]
        ),
    ]
)
