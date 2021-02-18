// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let sources = ["Qonversion/**"]

let package = Package(
    name: "Qonversion",
    platforms: [
        .iOS(.v9), .watchOS("6.2"), .macOS(.v10_12), .tvOS(.v9)
    ],
    products: [
        .library(
            name: "Qonversion",
            targets: ["Qonversion"]),
    ],
    targets: {
        let target: Target = .target(
            name: "Qonversion",
            path: "Sources",
            publicHeadersPath: "Qonversion/Public",
            cSettings: sources.map { .headerSearchPath($0) })

#if os(macOS) || os(tvOS) || os(watchOS)
        target.exclude = ["Automations"]
#endif

        return [target]
    }()
)
