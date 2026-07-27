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
//  Only Sources/ is scanned. This test target is deliberately exempt: it has to
//  spell the names out in order to assert they decode correctly, and it is
//  never shipped.
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
        let sourcesDirectory: URL = try sourcesDirectory()
        let fileManager: FileManager = FileManager.default

        let enumerator: FileManager.DirectoryEnumerator? = fileManager.enumerator(
            at: sourcesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        let unwrappedEnumerator: FileManager.DirectoryEnumerator = try XCTUnwrap(
            enumerator,
            "Could not enumerate \(sourcesDirectory.path)"
        )

        var scannedFileCount = 0
        var offences: [String] = []

        for case let fileURL as URL in unwrappedEnumerator {
            let resourceValues: URLResourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            guard let contents: String = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            scannedFileCount += 1

            for symbol in forbiddenSymbols where contents.contains(symbol) {
                let relativePath: String = fileURL.path.replacingOccurrences(of: sourcesDirectory.path, with: "Sources")
                offences.append("\(relativePath) mentions \"\(symbol)\"")
            }
        }

        // Guards the guard: a broken path would otherwise pass vacuously.
        XCTAssertGreaterThan(scannedFileCount, 100, "Scanned too few files — the source tree was probably not found")
        XCTAssertEqual(offences, [], "Shipped sources must not name the advertising framework symbols")
    }

    private func sourcesDirectory() throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot: URL = thisFile
            .deletingLastPathComponent() // QonversionUnitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
        let sourcesDirectory: URL = repositoryRoot.appendingPathComponent("Sources")

        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: sourcesDirectory.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists && isDirectory.boolValue, "Expected a source tree at \(sourcesDirectory.path)")

        return sourcesDirectory
    }
}
