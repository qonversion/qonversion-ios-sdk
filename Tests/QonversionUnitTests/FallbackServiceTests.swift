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
                {"id": "lite", "apple_product_id": "com.app.lite"}
            ],
            "products_permissions": {"pro": ["premium"], "lite": ["basic"]}
        }
        """
        let service = try makeService(fileContent: json)

        let fallback = service.obtainFallbackData()

        XCTAssertEqual(fallback?.products?.map(\.qonversionId), ["pro", "lite"])
        XCTAssertEqual(fallback?.products?.last?.storeId, "com.app.lite")
        XCTAssertEqual(fallback?.productsPermissions, ["pro": ["premium"], "lite": ["basic"]])
    }

    func testDecodesRemoteConfigList() throws {
        let json = """
        {
            "remote_config_list": [
                {
                    "payload": {"title": "Fallback title"},
                    "experiment": null,
                    "source": {"uid": "src-1", "name": "main-config", "type": "remote_configuration", "assignment_type": "auto", "context_key": "main"}
                },
                {
                    "payload": {"flag": true},
                    "experiment": null,
                    "source": {"uid": "src-2", "name": "default-config", "type": "remote_configuration", "assignment_type": "auto", "context_key": null}
                }
            ]
        }
        """
        let service = try makeService(fileContent: json)

        let fallback = service.obtainFallbackData()

        XCTAssertEqual(fallback?.remoteConfigs?.count, 2)
        XCTAssertEqual(fallback?.remoteConfigs?.first?.source?.contextKey, "main")
        XCTAssertEqual(fallback?.remoteConfigs?.first?.payload?["title"] as? String, "Fallback title")
        XCTAssertNil(fallback?.remoteConfigs?.last?.source?.contextKey)
    }

    // MARK: - the shipped ObjC contract

    func testTheObjCShapedFileDecodes() throws {
        // The file the previous SDK generation shipped keys the App Store id
        // as "store_id" (QNMapper.m), and MIGRATION.md promises the shape is
        // unchanged. Files already sitting in customers' bundles must work.
        let json = """
        {
            "products": [
                {"id": "pro", "store_id": "com.app.pro", "type": 1, "duration": 3},
                {"id": "lite", "store_id": "com.app.lite"}
            ],
            "products_permissions": {"pro": ["premium"], "consumable": []}
        }
        """
        let service = try makeService(fileContent: json)

        let fallback = service.obtainFallbackData()

        XCTAssertEqual(fallback?.products?.map(\.qonversionId), ["pro", "lite"])
        XCTAssertEqual(fallback?.products?.map(\.storeId), ["com.app.pro", "com.app.lite"])
        XCTAssertEqual(fallback?.productsPermissions, ["pro": ["premium"], "consumable": []])
    }

    func testStoreIdWinsOverAppleProductIdWhenBothArePresent() throws {
        let json = #"{"products": [{"id": "pro", "store_id": "from-store-id", "apple_product_id": "from-apple-product-id"}]}"#
        let service = try makeService(fileContent: json)

        XCTAssertEqual(service.obtainFallbackData()?.products?.first?.storeId, "from-store-id")
    }

    // MARK: - lossy rows

    func testOneMalformedProductRowDoesNotKillTheFile() throws {
        // The fallback file is the last line of defense: losing
        // products_permissions and remote_config_list over one bad product row
        // leaves the app with nothing at all.
        let json = """
        {
            "products": [{"id": "pro", "store_id": "com.app.pro"}, {"no_id": true}, 42],
            "products_permissions": {"pro": ["premium"]},
            "remote_config_list": [
                {"payload": {"k": "v"}, "experiment": null, "source": {"uid": "src-1", "name": "n", "type": "remote_configuration", "assignment_type": "auto", "context_key": "main"}}
            ]
        }
        """
        let service = try makeService(fileContent: json)

        let fallback = service.obtainFallbackData()

        XCTAssertEqual(fallback?.products?.map(\.qonversionId), ["pro"], "the malformed rows are skipped")
        XCTAssertEqual(fallback?.productsPermissions, ["pro": ["premium"]], "the other sections survive")
        XCTAssertEqual(fallback?.remoteConfigs?.count, 1)
    }

    func testOneMalformedRemoteConfigRowDoesNotKillTheFile() throws {
        let json = """
        {
            "products": [{"id": "pro", "store_id": "com.app.pro"}],
            "remote_config_list": [
                {"source": {}},
                {"payload": {"k": "v"}, "experiment": null, "source": {"uid": "src-1", "name": "n", "type": "remote_configuration", "assignment_type": "auto", "context_key": "main"}}
            ]
        }
        """
        let service = try makeService(fileContent: json)

        let fallback = service.obtainFallbackData()

        XCTAssertEqual(fallback?.products?.map(\.qonversionId), ["pro"])
        XCTAssertEqual(fallback?.remoteConfigs?.map { $0.source?.identifier }, ["src-1"])
    }

    func testOneMalformedPermissionsRelationDoesNotKillTheOthers() throws {
        let json = #"{"products_permissions": {"pro": ["premium"], "broken": 7}}"#
        let service = try makeService(fileContent: json)

        XCTAssertEqual(service.obtainFallbackData()?.productsPermissions, ["pro": ["premium"]])
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

// MARK: - Documents directory and re-checking

final class FallbackServiceLookupTests: XCTestCase {

    private var bundleDirectory: URL!
    private var documentsDirectory: URL!

    private let json = """
    {"products": [{"id": "main", "apple_product_id": "com.app.main"}]}
    """

    override func setUpWithError() throws {
        try super.setUpWithError()
        bundleDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("fallback-bundle-" + UUID().uuidString, isDirectory: true)
        documentsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("fallback-docs-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bundleDirectory)
        try? FileManager.default.removeItem(at: documentsDirectory)
        bundleDirectory = nil
        documentsDirectory = nil
        try super.tearDownWithError()
    }

    private func makeService() throws -> FallbackService {
        let bundle = try XCTUnwrap(Bundle(path: bundleDirectory.path))

        return FallbackService(bundle: bundle, decoder: JSONDecoder(), documentsDirectory: documentsDirectory)
    }

    private func writeFile(to directory: URL, content: String) throws {
        try Data(content.utf8).write(to: directory.appendingPathComponent("qonversion_ios_fallbacks.json"))
    }

    func testTheDocumentsCopyIsUsedWhenTheBundleHasNone() throws {
        // Production looks in the Documents directory too, so a file can be
        // dropped there at runtime.
        try writeFile(to: documentsDirectory, content: json)
        let service = try makeService()

        XCTAssertEqual(service.obtainFallbackData()?.products?.map { $0.qonversionId }, ["main"])
    }

    func testTheBundleWins() throws {
        try writeFile(to: bundleDirectory, content: #"{"products": [{"id": "bundled", "apple_product_id": "com.app.b"}]}"#)
        try writeFile(to: documentsDirectory, content: json)
        let service = try makeService()

        XCTAssertEqual(service.obtainFallbackData()?.products?.map { $0.qonversionId }, ["bundled"])
    }

    func testAMissingFileIsRecheckedOnTheNextCall() throws {
        // The negative outcome must not be cached forever: the file may be
        // written after the first call.
        let service = try makeService()
        XCTAssertNil(service.obtainFallbackData())

        try writeFile(to: documentsDirectory, content: json)

        XCTAssertNotNil(service.obtainFallbackData(), "a file that appeared later must be picked up")
    }

    func testAnUndecodableFileIsRecheckedOnTheNextCall() throws {
        try writeFile(to: documentsDirectory, content: "not json")
        let service = try makeService()
        XCTAssertNil(service.obtainFallbackData())

        try writeFile(to: documentsDirectory, content: json)

        XCTAssertNotNil(service.obtainFallbackData())
    }

    func testAccessibilityReflectsTheCurrentState() throws {
        let productsManager = ProductsManager(
            apiKey: "test_api_key",
            productsService: MockProductsService(),
            storeKitFacade: MockStoreKitFacade(),
            localStorage: MockLocalStorage(),
            fallbackService: try makeService(),
            logger: LoggerWrapper()
        )
        XCTAssertFalse(productsManager.isFallbackFileAccessible())

        try writeFile(to: documentsDirectory, content: json)

        XCTAssertTrue(productsManager.isFallbackFileAccessible(), "the debug check must reflect the file that is there now")
    }
}
