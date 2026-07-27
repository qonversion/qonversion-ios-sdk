//
//  FallbackServiceTests.swift
//  NoCodesTests
//
//  The bundled nocodes_fallbacks.json contract: lookup by context key and by
//  id, tolerated variable shapes, and the behavior without a file.
//

import XCTest
@testable import NoCodes

final class FallbackServiceTests: XCTestCase {

    private var bundleDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let temporaryDirectory: URL = FileManager.default.temporaryDirectory
        let name: String = "nocodes-fallback-tests-" + UUID().uuidString
        bundleDirectory = temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bundleDirectory)
        bundleDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Lookup

    func testLoadsAScreenByItsContextKey() throws {
        let service: FallbackService = try makeService(fileContent: twoScreensFile)

        let screen: NoCodesScreen = try XCTUnwrap(service.loadScreen(withContextKey: "onboarding"))

        XCTAssertEqual(screen.id, "screen-2")
        XCTAssertEqual(screen.contextKey, "onboarding")
        XCTAssertEqual(screen.html, "<html>two</html>")
    }

    func testLoadsAScreenByItsIdAcrossAllEntries() throws {
        let service: FallbackService = try makeService(fileContent: twoScreensFile)

        let screen: NoCodesScreen = try XCTUnwrap(service.loadScreen(with: "screen-1"))

        XCTAssertEqual(screen.contextKey, "main")
    }

    func testUnknownContextKeyResolvesToNothing() throws {
        let service: FallbackService = try makeService(fileContent: twoScreensFile)

        XCTAssertNil(service.loadScreen(withContextKey: "not-there"))
    }

    func testUnknownIdResolvesToNothing() throws {
        let service: FallbackService = try makeService(fileContent: twoScreensFile)

        XCTAssertNil(service.loadScreen(with: "not-there"))
    }

    // MARK: - Variables

    func testVariablesWithoutAKindDecodeAsCustomVariables() throws {
        let json = """
        {
          "screens": {
            "main": {
              "id": "screen-1",
              "body": "<html>one</html>",
              "context_key": "main",
              "variables": [
                {"key": "headline", "type": "string", "value": "Hello"},
                {"key": "discount", "type": "number", "value": 34}
              ]
            }
          }
        }
        """
        let service: FallbackService = try makeService(fileContent: json)

        let screen: NoCodesScreen = try XCTUnwrap(service.loadScreen(withContextKey: "main"))

        XCTAssertEqual(screen.defaultVariables.count, 2)
        XCTAssertEqual(screen.defaultVariable(forKey: "headline")?.kind, .custom)
        XCTAssertEqual(screen.defaultVariable(forKey: "discount")?.kind, .custom)
        XCTAssertEqual(screen.defaultVariable(forKey: "discount")?.value.stringValue, "34")
    }

    func testAFallbackScreenWithoutVariablesDecodes() throws {
        let service: FallbackService = try makeService(fileContent: twoScreensFile)

        let screen: NoCodesScreen = try XCTUnwrap(service.loadScreen(withContextKey: "main"))

        XCTAssertTrue(screen.defaultVariables.isEmpty)
        XCTAssertNil(screen.defaultSelectedProductId)
    }

    // MARK: - Missing and broken files

    func testAMissingFileResolvesToNothingForBothLookups() throws {
        let service: FallbackService = try makeService(fileContent: nil)

        XCTAssertNil(service.loadScreen(withContextKey: "main"))
        XCTAssertNil(service.loadScreen(with: "screen-1"))
    }

    func testAnUndecodableFileResolvesToNothing() throws {
        let service: FallbackService = try makeService(fileContent: "{\"screens\": \"not an object\"}")

        XCTAssertNil(service.loadScreen(withContextKey: "main"))
    }

    func testAvailabilityCheckReportsAMissingFile() throws {
        let bundle: Bundle = try makeBundle(fileContent: nil)

        XCTAssertFalse(FallbackService.isFallbackFileAvailable("nocodes_fallbacks.json", in: bundle))
    }

    func testAvailabilityCheckReportsAPresentFile() throws {
        let bundle: Bundle = try makeBundle(fileContent: twoScreensFile)

        XCTAssertTrue(FallbackService.isFallbackFileAvailable("nocodes_fallbacks.json", in: bundle))
    }

    func testACustomFileNameIsHonored() throws {
        let fileURL: URL = bundleDirectory.appendingPathComponent("custom_fallbacks.json")
        let data: Data = Data(twoScreensFile.utf8)
        try data.write(to: fileURL)
        let bundle: Bundle = try XCTUnwrap(Bundle(path: bundleDirectory.path))
        let logger = LoggerWrapper()
        let decoder = JSONDecoder()
        let service = FallbackService(logger: logger, bundle: bundle, fallbackFileName: "custom_fallbacks.json", decoder: decoder)

        XCTAssertNotNil(service.loadScreen(withContextKey: "main"))
    }

    // MARK: - Caching

    func testTheFileIsReadOnceAndServedFromTheCacheAfterwards() throws {
        let service: FallbackService = try makeService(fileContent: twoScreensFile)
        _ = service.loadScreen(withContextKey: "main")

        // Removing the file after the first read proves the second lookup is
        // served from the in-memory cache.
        let fileURL: URL = bundleDirectory.appendingPathComponent("nocodes_fallbacks.json")
        try FileManager.default.removeItem(at: fileURL)

        XCTAssertNotNil(service.loadScreen(withContextKey: "onboarding"))
    }

    // MARK: - Private

    private var twoScreensFile: String {
        return """
        {
          "screens": {
            "main": {"id": "screen-1", "body": "<html>one</html>", "context_key": "main"},
            "onboarding": {"id": "screen-2", "body": "<html>two</html>", "context_key": "onboarding"}
          }
        }
        """
    }

    private func makeBundle(fileContent: String?) throws -> Bundle {
        if let fileContent {
            let fileURL: URL = bundleDirectory.appendingPathComponent("nocodes_fallbacks.json")
            let data: Data = Data(fileContent.utf8)
            try data.write(to: fileURL)
        }

        return try XCTUnwrap(Bundle(path: bundleDirectory.path))
    }

    private func makeService(fileContent: String?) throws -> FallbackService {
        let bundle: Bundle = try makeBundle(fileContent: fileContent)
        let logger = LoggerWrapper()
        let decoder = JSONDecoder()

        return FallbackService(logger: logger, bundle: bundle, fallbackFileName: "nocodes_fallbacks.json", decoder: decoder)
    }
}
