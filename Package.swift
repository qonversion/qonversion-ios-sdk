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
        .library(
            name: "NoCodes",
            targets: ["NoCodes"]),
    ],
    targets: [
        .target(
            name: "Qonversion",
            path: "Sources",
            exclude: ["NoCodes"],
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]),
        .target(
            name: "NoCodes",
            dependencies: ["Qonversion"],
            path: "Sources/NoCodes",
            resources: [
                .copy("../PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]),
        .testTarget(
            name: "QonversionUnitTests",
            dependencies: ["Qonversion"],
            path: "Tests/QonversionUnitTests",
            resources: [
                .copy("Resources/Qonversion.storekit")
            ]),
        .testTarget(
            name: "NoCodesTests",
            dependencies: ["NoCodes"],
            path: "Tests/NoCodesTests"),
        // Talks to a REAL backend over a real socket; every test skips itself
        // unless QON_CONTRACT_BASE_URL points at one, so an ordinary
        // `swift test` stays offline.
        .testTarget(
            name: "QonversionContractTests",
            dependencies: ["Qonversion"],
            path: "Tests/QonversionContractTests"),
    ]
)
