// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Qonversion",
    platforms: [
        .iOS(.v15), .watchOS(.v8), .macOS(.v12), .tvOS(.v15), .visionOS(.v1)
    ],
    products: [
        .library(
            name: "Qonversion",
            targets: ["Qonversion"]),
    ],
    targets: [
        .target(
            name: "Qonversion",
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]),
        .testTarget(
            name: "QonversionUnitTests",
            dependencies: ["Qonversion"],
            path: "Tests/QonversionUnitTests"),
    ]
)
