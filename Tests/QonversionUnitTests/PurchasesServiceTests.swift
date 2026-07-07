//
//  PurchasesServiceTests.swift
//  QonversionUnitTests
//
//  Contract: POST v3/users/{uid}/purchases with price/currency/purchased and
//  app_store_data carrying the transaction ids and the jws proof in `receipt`
//  (per the gateway CreateUserPurchaseRequest model).
//

import XCTest
@testable import Qonversion

final class PurchasesServiceTests: XCTestCase {

    private func makeService(_ processor: MockRequestProcessor) -> PurchasesService {
        PurchasesService(requestProcessor: processor)
    }

    private func makeTransaction(
        id: String = "2000000123",
        originalId: String = "1000000123",
        productId: String = "com.app.pro",
        price: Decimal? = 9.99,
        currencyId: String? = "USD",
        purchaseDate: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        jws: String? = "signed-jws"
    ) -> Qonversion.Transaction {
        Qonversion.Transaction(
            id: id,
            originalId: originalId,
            productId: productId,
            purchaseDate: purchaseDate,
            price: price,
            currency: Qonversion.Currency(identifier: currencyId, symbol: nil),
            jws: jws
        )
    }

    func testSendPostsPurchaseWithAppStoreDataAndJwsProof() async throws {
        let processor = MockRequestProcessor()
        processor.results = [EmptyApiResponse()]
        let service = makeService(processor)

        try await service.send(makeTransaction(), userId: "QON_buyer")

        XCTAssertEqual(processor.processedRequests.count, 1)
        guard case let .createPurchase(userId, endpoint, body, type) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertEqual(userId, "QON_buyer")
        XCTAssertEqual(endpoint, "v3/users/%@/purchases")
        XCTAssertEqual(type, .post)

        XCTAssertEqual(body["price"] as? String, "9.99")
        XCTAssertEqual(body["currency"] as? String, "USD")
        XCTAssertEqual(body["purchased"] as? Int64, 1_700_000_000)

        let appStoreData = body["app_store_data"] as? RequestBodyDict
        XCTAssertEqual(appStoreData?["transaction_id"] as? String, "2000000123")
        XCTAssertEqual(appStoreData?["original_transaction_id"] as? String, "1000000123")
        XCTAssertEqual(appStoreData?["product_id"] as? String, "com.app.pro")
        XCTAssertEqual(appStoreData?["receipt"] as? String, "signed-jws", "the jws proof travels in app_store_data.receipt")
    }

    func testSendWithOptionsIncludesContextKeysAndScreenUid() async throws {
        let processor = MockRequestProcessor()
        processor.results = [EmptyApiResponse()]
        let service = makeService(processor)
        let options = Qonversion.PurchaseOptions(contextKeys: ["main", "onboarding"], screenUid: "screen_1")

        try await service.send(makeTransaction(), userId: "QON_buyer", options: options)

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertEqual(body["context_keys"] as? [String], ["main", "onboarding"])
        XCTAssertEqual(body["screen_uid"] as? String, "screen_1")
    }

    func testSendWithoutOptionsOmitsAssociationFields() async throws {
        let processor = MockRequestProcessor()
        processor.results = [EmptyApiResponse()]
        let service = makeService(processor)

        try await service.send(makeTransaction(), userId: "QON_buyer")

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertNil(body["context_keys"])
        XCTAssertNil(body["screen_uid"])
    }

    func testSendWithoutJwsSendsEmptyReceipt() async throws {
        let processor = MockRequestProcessor()
        processor.results = [EmptyApiResponse()]
        let service = makeService(processor)

        try await service.send(makeTransaction(jws: nil), userId: "QON_buyer")

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        let appStoreData = body["app_store_data"] as? RequestBodyDict
        XCTAssertEqual(appStoreData?["receipt"] as? String, "")
    }

    func testSendWrapsErrorsIntoPurchaseReportingFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = makeService(processor)

        do {
            try await service.send(makeTransaction(), userId: "QON_buyer")
            XCTFail("Expected send to throw")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseReportingFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
