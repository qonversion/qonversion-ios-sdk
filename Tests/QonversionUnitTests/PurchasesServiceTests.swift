//
//  PurchasesServiceTests.swift
//  QonversionUnitTests
//
//  Contract: POST v4/users/{uid}/purchases with price/currency/purchased and
//  app_store_data carrying the transaction ids and the jws proof in `receipt`
//  (per the gateway CreateUserPurchaseRequest model).
//

import XCTest
@testable import Qonversion

final class PurchasesServiceTests: XCTestCase {

    private func makeService(_ processor: MockRequestProcessor) -> PurchasesService {
        PurchasesService(requestProcessor: processor, appBundleId: "com.test.app")
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
        XCTAssertEqual(endpoint, "v4/users/%@/purchases")
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

    // MARK: - promotional offer signature

    func testPromotionalOfferPostsSignatureRequestAndMapsResponse() async throws {
        let processor = MockRequestProcessor()
        let nonce = UUID()
        processor.results = [PromoOfferSignatureResponse(
            keyIdentifier: "KEY123",
            signature: Data([0x01, 0x02]).base64EncodedString(),
            nonce: nonce.uuidString,
            timestamp: "1700000000000"
        )]
        let service = PurchasesService(requestProcessor: processor, appBundleId: "com.test.app")

        let offer = try await service.promotionalOffer(userId: "QON_buyer", offerId: "offer1", productStoreId: "com.app.pro")

        guard case let .signPromoOffer(userId, offerId, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a signPromoOffer request")
        }
        XCTAssertEqual(userId, "QON_buyer")
        XCTAssertEqual(offerId, "offer1")
        XCTAssertEqual(body["product"] as? String, "com.app.pro")
        // The token participates in the signed payload and must match the
        // purchase, which sets no appAccountToken — so it stays empty.
        XCTAssertEqual(body["app_account_token"] as? String, "")
        XCTAssertEqual(body["app_bundle_id"] as? String, "com.test.app")

        XCTAssertEqual(offer.offerId, "offer1")
        XCTAssertEqual(offer.keyId, "KEY123")
        XCTAssertEqual(offer.nonce, nonce)
        XCTAssertEqual(offer.signature, Data([0x01, 0x02]))
        XCTAssertEqual(offer.timestamp, 1_700_000_000_000)
    }

    func testPromotionalOfferWithMalformedSignatureThrows() async {
        let processor = MockRequestProcessor()
        processor.results = [PromoOfferSignatureResponse(keyIdentifier: "KEY123", signature: "%%%", nonce: "not-a-uuid", timestamp: "soon")]
        let service = PurchasesService(requestProcessor: processor, appBundleId: "com.test.app")

        do {
            _ = try await service.promotionalOffer(userId: "u", offerId: "o", productStoreId: "p")
            XCTFail("Expected a mapping error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .promoOfferSigningFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPromotionalOfferWrapsProcessorErrors() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = PurchasesService(requestProcessor: processor, appBundleId: "com.test.app")

        do {
            _ = try await service.promotionalOffer(userId: "u", offerId: "o", productStoreId: "p")
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .promoOfferSigningFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
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
