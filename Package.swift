// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Qonversion",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "Qonversion",
            targets: ["Qonversion"]
        ),
        .library(
            name: "NoCodes",
            targets: ["NoCodes"]
        )
    ],
    targets: [
        .target(
            name: "Qonversion",
            path: "Sources/Qonversion",
            exclude: [],
            resources: [
                .copy("../PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ]
        ),
        .target(
            name: "NoCodes",
            dependencies: ["Qonversion"],
            path: "Sources/NoCodes",
            resources: [
                .copy("../PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .define("SWIFT_PACKAGE")
            ]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["Qonversion", "NoCodes"],
            path: "IntegrationTests",
            exclude: [],
            resources: [
                .copy("Resources")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
