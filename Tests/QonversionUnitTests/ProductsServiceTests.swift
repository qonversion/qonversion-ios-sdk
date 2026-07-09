//
//  ProductsServiceTests.swift
//  QonversionUnitTests
//
//  Fixation tests for ProductsService: locks in current behavior as-is.
//

import XCTest
@testable import Qonversion

final class ProductsServiceTests: XCTestCase {

    func testProductsSendsGetProductsRequestAndReturnsProcessorResult() async throws {
        let processor = MockRequestProcessor()
        let config = InternalConfig(userId: "QON_products_user")
        let service = ProductsService(requestProcessor: processor, internalConfig: config)

        let stubProducts: [Qonversion.Product] = [
            Qonversion.Product(qonversionId: "main", storeId: "com.app.main", offeringId: "offering_1"),
            Qonversion.Product(qonversionId: "secondary", storeId: "com.app.secondary", offeringId: nil)
        ]
        processor.results = [ListEnvelope<Qonversion.Product>(data: stubProducts)]

        let products = try await service.products()

        XCTAssertEqual(processor.processedRequests, [Request.getProducts()])
        XCTAssertEqual(products.count, 2)
        XCTAssertEqual(products[0].qonversionId, "main")
        XCTAssertEqual(products[0].storeId, "com.app.main")
        XCTAssertEqual(products[0].offeringId, "offering_1")
        XCTAssertEqual(products[1].qonversionId, "secondary")
        XCTAssertNil(products[1].offeringId)
    }

    func testProductsReturnsEmptyArrayFromProcessor() async throws {
        let processor = MockRequestProcessor()
        let service = ProductsService(requestProcessor: processor, internalConfig: InternalConfig(userId: "QON_products_user"))
        processor.results = [ListEnvelope<Qonversion.Product>(data: [])]

        let products = try await service.products()

        XCTAssertTrue(products.isEmpty)
    }

    func testProductsWrapsProcessorErrorIntoProductsLoadingFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = ProductsService(requestProcessor: processor, internalConfig: InternalConfig(userId: "QON_products_user"))

        do {
            _ = try await service.products()
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .productsLoadingFailed)
            XCTAssertEqual(error.error as? MockError, .stubbed)
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    // MARK: - product permissions

    func testProductPermissionsInvertsEntitlementDefinitions() async throws {
        let processor = MockRequestProcessor()
        // v4: GET /v4/entitlements returns the dashboard definitions with
        // their unlocking products; the SDK inverts them.
        processor.results = [ListEnvelope<EntitlementDefinition>(data: [
            EntitlementDefinition(id: "premium", productIds: ["pro", "pro_yearly"]),
            EntitlementDefinition(id: "extra", productIds: ["pro"]),
            EntitlementDefinition(id: "orphan", productIds: []),
        ])]
        let service = ProductsService(requestProcessor: processor, internalConfig: InternalConfig(userId: "QON_x"))

        let result = try await service.productPermissions()

        XCTAssertEqual(processor.processedRequests, [Request.entitlementDefinitions()])
        XCTAssertEqual(result["pro"]?.sorted(), ["extra", "premium"])
        XCTAssertEqual(result["pro_yearly"], ["premium"])
        XCTAssertNil(result["orphan"], "a definition without products grants nothing")
    }

    func testProductPermissionsWrapsErrors() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = ProductsService(requestProcessor: processor, internalConfig: InternalConfig(userId: "QON_x"))

        do {
            _ = try await service.productPermissions()
            XCTFail("Expected productPermissions to throw")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .productPermissionsLoadingFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
