//
//  FallbackServiceTests.swift
//  QonversionUnitTests
//
//  The bundled fallback file (qonversion_ios_fallbacks.json) powers products
//  and the product → permissions mapping when the API is unreachable and no
//  cache exists yet (TDD — written before the implementation).
//

import XCTest
@testable import Qonversion

final class FallbackServiceTests: XCTestCase {

    private var bundleDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        bundleDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fallback-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bundleDirectory)
        bundleDirectory = nil
        try super.tearDownWithError()
    }

    private func makeService(fileContent: String?) throws -> FallbackService {
        if let fileContent {
            let fileURL = bundleDirectory.appendingPathComponent("qonversion_ios_fallbacks.json")
            try Data(fileContent.utf8).write(to: fileURL)
        }
        let bundle = try XCTUnwrap(Bundle(path: bundleDirectory.path))
        return FallbackService(bundle: bundle, decoder: JSONDecoder())
    }

    func testDecodesProductsAndPermissionsMapping() throws {
        let json = """
        {
            "products": [
                {"id": "pro", "apple_product_id": "com.app.pro"},
                {"id": "lite", "apple_product_id": "com.app.lite", "offering_id": "main"}
            ],
            "products_permissions": {"pro": ["premium"], "lite": ["basic"]}
        }
        """
        let service = try makeService(fileContent: json)

        let fallback = service.obtainFallbackData()

        XCTAssertEqual(fallback?.products?.map(\.qonversionId), ["pro", "lite"])
        XCTAssertEqual(fallback?.products?.last?.offeringId, "main")
        XCTAssertEqual(fallback?.productsPermissions, ["pro": ["premium"], "lite": ["basic"]])
    }

    func testMissingFileReturnsNil() throws {
        let service = try makeService(fileContent: nil)

        XCTAssertNil(service.obtainFallbackData())
    }

    func testMalformedFileReturnsNil() throws {
        let service = try makeService(fileContent: "not a json")

        XCTAssertNil(service.obtainFallbackData())
    }

    func testPartialFileDecodesAvailableSections() throws {
        let service = try makeService(fileContent: #"{"products_permissions": {"pro": ["premium"]}}"#)

        let fallback = service.obtainFallbackData()

        XCTAssertNil(fallback?.products)
        XCTAssertEqual(fallback?.productsPermissions, ["pro": ["premium"]])
    }
}
