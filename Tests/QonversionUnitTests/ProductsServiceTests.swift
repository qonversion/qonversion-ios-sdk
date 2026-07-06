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
        processor.results = [stubProducts]

        let products = try await service.products()

        XCTAssertEqual(processor.processedRequests, [Request.getProducts(userId: "QON_products_user")])
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
        processor.results = [[Qonversion.Product]()]

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
}
