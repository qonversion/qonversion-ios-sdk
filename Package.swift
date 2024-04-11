// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Qonversion",
    platforms: [
        .iOS(.v13), .watchOS(.v6), .macOS(.v10_15), .tvOS(.v13)
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
            ]),
    ]
)
