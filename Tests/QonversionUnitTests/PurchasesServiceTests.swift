//
//  PurchasesServiceTests.swift
//  QonversionUnitTests
//
//  Contract: POST v4/users/{uid}/purchases — platform + store_data (typed per
//  store, app_store shape carries the transaction ids and the jws proof in
//  `receipt`), price/currency/purchased_at at the top level.
//

import XCTest
@testable import Qonversion


final class PurchasesServiceTests: XCTestCase {

    // MARK: - proof of purchase

    func testReportCarriesTheJwsProof() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = PurchasesService(requestProcessor: processor, appBundleId: "com.test.app")
        let transaction = Qonversion.Transaction(id: "t1", originalId: "t1", productId: "com.app.pro", jws: "signed-jws")

        try await service.send(transaction, userId: "user_abc", options: nil, trigger: .purchase)

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests[0] else {
            return XCTFail("Expected a .createPurchase request")
        }
        let storeData = body["store_data"] as? RequestBodyDict
        XCTAssertEqual(storeData?["receipt"] as? String, "signed-jws")
    }

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

    func testSendPostsPurchaseWithV4StoreDataAndJwsProof() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)

        try await service.send(makeTransaction(), userId: "QON_buyer")

        XCTAssertEqual(processor.processedRequests.count, 1)
        guard case let .createPurchase(userId, endpoint, body, type) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertEqual(userId, "QON_buyer")
        XCTAssertEqual(endpoint, "v4/users/%@/purchases")
        XCTAssertEqual(type, .post)

        XCTAssertEqual(body["platform"] as? String, "app_store")
        XCTAssertEqual(body["price"] as? String, "9.99")
        XCTAssertEqual(body["currency"] as? String, "USD")
        XCTAssertEqual(body["purchased_at"] as? String, "2023-11-14T22:13:20Z")

        let storeData = body["store_data"] as? RequestBodyDict
        XCTAssertEqual(storeData?["transaction_id"] as? String, "2000000123")
        XCTAssertEqual(storeData?["original_transaction_id"] as? String, "1000000123")
        XCTAssertEqual(storeData?["product_id"] as? String, "com.app.pro")
        XCTAssertEqual(storeData?["receipt"] as? String, "signed-jws", "the jws proof travels in store_data.receipt")
    }

    func testSendWithoutPurchaseDateOmitsPurchasedAt() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)

        try await service.send(makeTransaction(purchaseDate: nil), userId: "QON_buyer")

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertNil(body["purchased_at"], "the backend derives the date from the jws when the client has none")
    }

    func testSendWithOptionsIncludesContextKeysAndScreenUid() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)
        let options = Qonversion.PurchaseOptions(contextKeys: ["main", "onboarding"], screenUid: "screen_1")

        try await service.send(makeTransaction(), userId: "QON_buyer", options: options)

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertEqual(body["context_keys"] as? [String], ["main", "onboarding"])
        XCTAssertEqual(body["screen_uid"] as? String, "screen_1")
    }

    func testSendFiltersEmptyContextKeysAndOmitsTheFieldWhenNoneAreLeft() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)
        let options = Qonversion.PurchaseOptions(contextKeys: ["", "main", ""])

        try await service.send(makeTransaction(), userId: "QON_buyer", options: options)

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertEqual(body["context_keys"] as? [String], ["main"], "a blank context key must not reach the backend")
    }

    func testSendOmitsContextKeysWhenEveryOneIsEmpty() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)
        let options = Qonversion.PurchaseOptions(contextKeys: [""])

        try await service.send(makeTransaction(), userId: "QON_buyer", options: options)

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertNil(body["context_keys"])
    }

    func testSendOmitsAnEmptyScreenUid() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)
        let options = Qonversion.PurchaseOptions(screenUid: "")

        try await service.send(makeTransaction(), userId: "QON_buyer", options: options)

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertNil(body["screen_uid"])
    }

    func testSendOmitsAScreenUidLongerThanTheBackendColumn() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)
        let options = Qonversion.PurchaseOptions(screenUid: String(repeating: "a", count: 256))

        try await service.send(makeTransaction(), userId: "QON_buyer", options: options)

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertNil(body["screen_uid"], "an oversized value must not take the whole report down with it")
    }

    func testSendIncludesAScreenUidAtTheColumnLimit() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)
        let screenUid = String(repeating: "a", count: 255)
        let options = Qonversion.PurchaseOptions(screenUid: screenUid)

        try await service.send(makeTransaction(), userId: "QON_buyer", options: options)

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertEqual(body["screen_uid"] as? String, screenUid)
    }

    func testSendWithoutOptionsOmitsAssociationFields() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)

        try await service.send(makeTransaction(), userId: "QON_buyer")

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertNil(body["context_keys"])
        XCTAssertNil(body["screen_uid"])
    }

    // MARK: - price / currency

    /// An unknown price must be absent from the body, never an empty string:
    /// the backend reads "" as a value and would record a zero-cost purchase.
    func testSendWithoutPriceOmitsThePriceKey() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)

        try await service.send(makeTransaction(price: nil), userId: "QON_buyer")

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertNil(body["price"])
        XCTAssertNil(body["currency"], "price and currency are sent only as a complete pair")
    }

    func testSendWithoutCurrencyOmitsTheCurrencyKey() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)

        try await service.send(makeTransaction(currencyId: nil), userId: "QON_buyer")

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertNil(body["currency"])
        XCTAssertNil(body["price"], "price and currency are sent only as a complete pair")
    }

    /// An identifier that is present but empty is as unknown as a missing one.
    func testSendWithEmptyCurrencyIdentifierOmitsTheCurrencyKey() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)

        try await service.send(makeTransaction(currencyId: ""), userId: "QON_buyer")

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertNil(body["currency"])
        XCTAssertNil(body["price"], "an empty currency makes the whole pair unknown")
    }

    func testSendWithoutPriceAndCurrencyKeepsTheRestOfTheBody() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)

        try await service.send(makeTransaction(price: nil, currencyId: nil), userId: "QON_buyer")

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        XCTAssertNil(body["price"])
        XCTAssertNil(body["currency"])
        XCTAssertEqual(body["platform"] as? String, "app_store")
        XCTAssertEqual(body["purchased_at"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertNotNil(body["store_data"])
    }

    func testSendWithoutJwsSendsEmptyReceipt() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PurchaseReportResponse(userId: nil)]
        let service = makeService(processor)

        try await service.send(makeTransaction(jws: nil), userId: "QON_buyer")

        guard case let .createPurchase(_, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a createPurchase request")
        }
        let storeData = body["store_data"] as? RequestBodyDict
        XCTAssertEqual(storeData?["receipt"] as? String, "")
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

    // MARK: - promotional offer: real request pipeline (v4 route)

    /// The REAL processor over a stubbed transport, exactly like
    /// EntitlementsServiceTests: proves the request actually leaves for the
    /// v4 path and that the real error handler's mapping (including
    /// secrets_not_found) survives the service's own error wrapping.
    private func makeLivePurchasesService(responseData: Data, statusCode: Int) -> (PurchasesService, MockNetworkProvider) {
        let networkProvider = MockNetworkProvider()
        networkProvider.responseData = responseData
        networkProvider.response = HTTPURLResponse(
            url: URL(string: "https://api2.qonversion.io/v4/users/QON_buyer/offers/offer1/signatures")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        let internalConfig = InternalConfig(userId: "QON_buyer")
        let miscAssembly = MiscAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated(), internalConfig: internalConfig)
        let processor = RequestProcessor(
            baseURL: "https://api2.qonversion.io/",
            networkProvider: networkProvider,
            headersBuilder: MockHeadersBuilder(),
            errorHandler: miscAssembly.errorHandler(),
            decoder: miscAssembly.responseDecoder(),
            retriableRequestKinds: [],
            requestsStorage: MockRequestsStorage(),
            rateLimiter: MockRateLimiter()
        )

        return (PurchasesService(requestProcessor: processor, appBundleId: "com.test.app"), networkProvider)
    }

    func testPromotionalOfferPostsToTheV4SignaturesRouteAndDecodesTheResponse() async throws {
        let json = #"{"key_identifier": "KEY123", "nonce": "9E76F7BE-2E9D-4B1B-9A5D-2B1A6B7B0A11", "signature": "AQI=", "timestamp": "1700000000000"}"#
        let (service, networkProvider) = makeLivePurchasesService(responseData: Data(json.utf8), statusCode: 200)

        let offer = try await service.promotionalOffer(userId: "QON_buyer", offerId: "offer1", productStoreId: "com.app.pro")

        XCTAssertEqual(networkProvider.sentRequests.first?.url?.absoluteString, "https://api2.qonversion.io/v4/users/QON_buyer/offers/offer1/signatures")
        XCTAssertEqual(networkProvider.sentRequests.first?.httpMethod, "POST")
        XCTAssertEqual(offer.keyId, "KEY123")
        XCTAssertEqual(offer.timestamp, 1_700_000_000_000, "timestamp is a millisecond STRING on the wire")
    }

    func testPromotionalOfferForwardsTheLowercasedAppAccountToken() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PromoOfferSignatureResponse(
            keyIdentifier: "KEY123",
            signature: Data([0x01, 0x02]).base64EncodedString(),
            nonce: UUID().uuidString,
            timestamp: "1700000000000"
        )]
        let service = PurchasesService(requestProcessor: processor, appBundleId: "com.test.app")
        let token = UUID(uuidString: "9E76F7BE-2E9D-4B1B-9A5D-2B1A6B7B0A11")!

        _ = try await service.promotionalOffer(userId: "u", offerId: "o", productStoreId: "p", appAccountToken: token)

        guard case let .signPromoOffer(_, _, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a signPromoOffer request")
        }
        // The App Store checks the signature against the token lowercased, as
        // it signs its own — an uppercased mismatch would make it refuse the offer.
        XCTAssertEqual(body["app_account_token"] as? String, "9e76f7be-2e9d-4b1b-9a5d-2b1a6b7b0a11")
    }

    func testPromotionalOfferWithoutAnAppAccountTokenSendsAnEmptyOne() async throws {
        let processor = MockRequestProcessor()
        processor.results = [PromoOfferSignatureResponse(
            keyIdentifier: "KEY123",
            signature: Data([0x01, 0x02]).base64EncodedString(),
            nonce: UUID().uuidString,
            timestamp: "1700000000000"
        )]
        let service = PurchasesService(requestProcessor: processor, appBundleId: "com.test.app")

        _ = try await service.promotionalOffer(userId: "u", offerId: "o", productStoreId: "p", appAccountToken: nil)

        guard case let .signPromoOffer(_, _, _, body, _) = processor.processedRequests.first else {
            return XCTFail("Expected a signPromoOffer request")
        }
        XCTAssertEqual(body["app_account_token"] as? String, "")
    }

    func testPromotionalOfferNotEligibleIsNotWrappedIntoSigningFailed() async {
        // "Not eligible" is the backend's verdict on the offer, not a failure
        // of the call — it must stay distinguishable from every other error.
        let json = #"{"error": {"code": "not_eligible", "message": "no eligible history"}}"#
        let (service, _) = makeLivePurchasesService(responseData: Data(json.utf8), statusCode: 422)

        do {
            _ = try await service.promotionalOffer(userId: "QON_buyer", offerId: "offer1", productStoreId: "com.app.pro")
            XCTFail("Expected a not_eligible error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .promoOfferNotEligible)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPromotionalOfferOnTheV4RouteStillMapsSecretsNotFound() async {
        // The reason for the v4 switch: the project has no App Store Connect
        // credentials, so the signature service answers 422 secrets_not_found.
        let json = #"{"error": {"code": "secrets_not_found", "message": "no credentials"}}"#
        let (service, _) = makeLivePurchasesService(responseData: Data(json.utf8), statusCode: 422)

        do {
            _ = try await service.promotionalOffer(userId: "QON_buyer", offerId: "offer1", productStoreId: "com.app.pro")
            XCTFail("Expected a mapping error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .promoOfferSigningFailed, "the service still names its own operation as the failure")
            XCTAssertEqual(error.apiCode, "secrets_not_found", "the backend slug must survive the service's own error wrapping")
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
