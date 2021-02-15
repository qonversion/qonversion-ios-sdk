// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Qonversion",
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
        
#if os(macOS) || os(watchOS) || os(tvOS)
        target.exclude = ["Sources/Qonversion/QONAutomations*", "Sources/Qonversion/QONActionResult.{h,m}"]
#endif

        return [target]
    }()
)
