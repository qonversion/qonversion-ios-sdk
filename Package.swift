// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let sources: [String] = ["Qonversion/**"]

func generateHeaderSearchPaths() -> [String] {
    var currentDirectoryPath = #filePath
    currentDirectoryPath.removeSubrange(#filePath.range(of: "Package.swift")!)
    let pathString = currentDirectoryPath + "Sources/"
    var paths = [String]()
    if let enumerator = FileManager.default.enumerator(at: URL(string: pathString)!, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
        for case let fileURL as URL in enumerator {
            do {
                let fileAttributes = try fileURL.resourceValues(forKeys:[.isDirectoryKey])
                if fileAttributes.isDirectory! {
                    var result = fileURL.absoluteString.replacingOccurrences(of: "file://"+pathString, with: "", options: [], range: nil)
                    result.removeLast()

                    paths.append(result)
                }
            } catch { print(error, fileURL) }
        }
    }
    
    return paths
}

let headerSearchPaths = generateHeaderSearchPaths()

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
                cSettings: headerSearchPaths.map { .headerSearchPath($0) })]
)
