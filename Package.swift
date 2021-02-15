// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
            exclude: [],
            publicHeadersPath: ".")
        
#if os(macOS)
        target.exclude = ["Qonversion/Sources/QONAutomationsViewController.h", "Qonversion/Sources/QONAutomationsViewController.m"]
#endif

        return [target]
    }()
)
