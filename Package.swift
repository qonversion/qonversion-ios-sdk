// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let sources: [String] = ["Qonversion/**"]

let package = Package(
    name: "Qonversion",
    platforms: [
        .iOS(.v9), .watchOS("6.2"), .macOS(.v10_12), .tvOS(.v9)
    ],
    products: [
        .library(
            name: "Qonversion",
            targets: ["Qonversion"])
    ],
    targets: [.target(
                name: "Qonversion",
                path: "Sources",
                publicHeadersPath: "Qonversion/Public",
                cSettings: sources.map { .headerSearchPath($0) })]
)
