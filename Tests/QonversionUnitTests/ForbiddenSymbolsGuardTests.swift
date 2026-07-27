//
//  ForbiddenSymbolsGuardTests.swift
//  QonversionUnitTests
//
//  A build-time guard, not a behaviour test. The SDK must never name the
//  advertising framework or its symbols in shipped sources: App Review scans
//  the compiled binary for those strings, and a match makes the SDK unusable in
//  apps that declare no tracking — Kids Category apps above all. See
//  AdvertisingIdReader for the full reasoning and the reflection path that
//  replaces the linkage.
//
//  Sources/ is scanned, and so are the two build manifests: the linkage can be
//  restored from Package.swift (`.linkedFramework`) or from the Xcode project
//  (a frameworks build phase, or OTHER_LDFLAGS) without a single line of Swift
//  changing. This test target is deliberately exempt: it has to spell the names
//  out in order to assert they decode correctly, and it is never shipped.
//

import XCTest

final class ForbiddenSymbolsGuardTests: XCTestCase {

    private let forbiddenSymbols: [String] = [
        "AdSupport",
        "ASIdentifierManager",
        "advertisingIdentifier",
        "sharedManager",
    ]

    func testShippedSourcesNeverNameTheAdvertisingFrameworkSymbols() throws {
        let repositoryRoot: URL = repositoryRoot()
        let scannedFiles: [URL] = try scannedFiles(in: repositoryRoot)
        var offences: [String] = []

        for fileURL in scannedFiles {
            let relativePath: String = fileURL.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")

            // Not skipped: a file this test cannot read is a file it cannot
            // vouch for, and silently passing over it is how the guard would
            // rot without anyone noticing.
            guard let contents: String = try? String(contentsOf: fileURL, encoding: .utf8) else {
                XCTFail("Could not read \(relativePath) as UTF-8, so it could not be checked")
                continue
            }

            for symbol in forbiddenSymbols where contents.contains(symbol) {
                offences.append("\(relativePath) mentions \"\(symbol)\"")
            }
        }

        // Guards the guard: a broken path would otherwise pass vacuously.
        XCTAssertGreaterThan(scannedFiles.count, 100, "Scanned too few files — the source tree was probably not found")
        XCTAssertEqual(offences, [], "Shipped sources and build manifests must not name the advertising identifier framework")
    }

    /// Everything under `Sources/`, plus the two manifests that can restore the
    /// linkage without any Swift file changing.
    private func scannedFiles(in repositoryRoot: URL) throws -> [URL] {
        let sourcesDirectory: URL = repositoryRoot.appendingPathComponent("Sources")

        var isDirectory: ObjCBool = false
        let sourcesExist: Bool = FileManager.default.fileExists(atPath: sourcesDirectory.path, isDirectory: &isDirectory)
        XCTAssertTrue(sourcesExist && isDirectory.boolValue, "Expected a source tree at \(sourcesDirectory.path)")

        let enumerator: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(
            at: sourcesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        let unwrappedEnumerator: FileManager.DirectoryEnumerator = try XCTUnwrap(
            enumerator,
            "Could not enumerate \(sourcesDirectory.path)"
        )

        var files: [URL] = []
        for case let fileURL as URL in unwrappedEnumerator {
            let resourceValues: URLResourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }

            files.append(fileURL)
        }

        let manifests: [URL] = [
            repositoryRoot.appendingPathComponent("Package.swift"),
            repositoryRoot.appendingPathComponent("Qonversion.xcodeproj/project.pbxproj"),
        ]
        for manifest in manifests {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: manifest.path),
                "Expected a build manifest at \(manifest.path) — the guard must not lose sight of it"
            )
            files.append(manifest)
        }

        return files
    }

    private func repositoryRoot() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)

        return thisFile
            .deletingLastPathComponent() // QonversionUnitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
    }
}
