//
//  OfferingsTests.swift
//  QonversionUnitTests
//
//  Offerings: the user-scoped GET /v4/users/{user_id}/offerings handle returns
//  offerings with full embedded product objects in the paywall order; tag 1
//  marks the main offering (TDD — written before the implementation).
//

import XCTest
import StoreKit
@testable import Qonversion

final class OfferingsTests: XCTestCase {

    // MARK: - Decoding

    private let decoder = JSONDecoder()

    private func decodeList(_ json: String) throws -> [Qonversion.Offering] {
        let envelope: ListEnvelope<Qonversion.Offering> = try decoder.decode(ListEnvelope<Qonversion.Offering>.self, from: Data(json.utf8))
        return envelope.data
    }

    func testDecodesOfferingsListWithEmbeddedProducts() throws {
        let json = """
        {
            "object": "list",
            "url": "/v4/users/user_abc/offerings",
            "data": [
                {
                    "object": "offering",
                    "id": "main_paywall",
                    "url": "/v4/offerings/main_paywall",
                    "tag": 1,
                    "products": [
                        {"object": "product", "id": "pro_annual", "apple_product_id": "com.app.pro.y", "offering_id": "main_paywall"},
                        {"object": "product", "id": "pro_monthly", "apple_product_id": "com.app.pro.m", "offering_id": "main_paywall"}
                    ]
                },
                {
                    "object": "offering",
                    "id": "secondary",
                    "url": "/v4/offerings/secondary",
                    "tag": 0,
                    "products": [
                        {"object": "product", "id": "lite", "apple_product_id": "com.app.lite", "offering_id": "secondary"}
                    ]
                }
            ]
        }
        """

        let offerings: [Qonversion.Offering] = try decodeList(json)

        XCTAssertEqual(offerings.map(\.id), ["main_paywall", "secondary"])
        XCTAssertEqual(offerings[0].tag, .main)
        XCTAssertEqual(offerings[1].tag, .none)
        // The array order is the paywall order — it must survive decoding.
        XCTAssertEqual(offerings[0].products.map(\.qonversionId), ["pro_annual", "pro_monthly"])
        XCTAssertEqual(offerings[0].products.map(\.storeId), ["com.app.pro.y", "com.app.pro.m"])
        XCTAssertEqual(offerings[0].products.first?.offeringId, "main_paywall")
        XCTAssertEqual(offerings[1].products.map(\.qonversionId), ["lite"])
    }

    func testDecodingToleratesMissingTagAndProducts() throws {
        let json = #"{"object": "list", "data": [{"object": "offering", "id": "bare"}]}"#

        let offerings: [Qonversion.Offering] = try decodeList(json)

        XCTAssertEqual(offerings.first?.id, "bare")
        XCTAssertEqual(offerings.first?.tag, Qonversion.Offering.Tag.none)
        XCTAssertEqual(offerings.first?.products.count, 0)
    }

    func testDecodingMapsUnknownTagValueToNone() throws {
        let json = #"{"object": "list", "data": [{"object": "offering", "id": "exotic", "tag": 42, "products": []}]}"#

        let offerings: [Qonversion.Offering] = try decodeList(json)

        XCTAssertEqual(offerings.first?.tag, Qonversion.Offering.Tag.none)
    }

    // MARK: - Offerings entity

    private func makeOffering(id: String, tag: Qonversion.Offering.Tag, productIds: [String] = []) -> Qonversion.Offering {
        let products: [Qonversion.Product] = productIds.map { Qonversion.Product(qonversionId: $0, storeId: "store_" + $0, offeringId: id) }
        return Qonversion.Offering(id: id, tag: tag, products: products)
    }

    func testOfferingsMainIsTheTagOneOffering() {
        let secondary: Qonversion.Offering = makeOffering(id: "secondary", tag: .none)
        let main: Qonversion.Offering = makeOffering(id: "main_paywall", tag: .main)
        let offerings = Qonversion.Offerings(offerings: [secondary, main])

        XCTAssertEqual(offerings.main?.id, "main_paywall")
        XCTAssertEqual(offerings.availableOfferings.map(\.id), ["secondary", "main_paywall"])
    }

    func testOfferingsMainIsNilWithoutTagOne() {
        let offerings = Qonversion.Offerings(offerings: [makeOffering(id: "secondary", tag: .none)])

        XCTAssertNil(offerings.main)
    }

    func testOfferingForIdentifierLookup() {
        let offerings = Qonversion.Offerings(offerings: [
            makeOffering(id: "a", tag: .none),
            makeOffering(id: "b", tag: .main),
        ])

        XCTAssertEqual(offerings.offering(for: "b")?.id, "b")
        XCTAssertNil(offerings.offering(for: "missing"))
    }

    // MARK: - Request

    func testGetOfferingsRequestIsUserScopedAndEscaped() throws {
        let request = try XCTUnwrap(Request.getOfferings(userId: "user 1").convertToURLRequest("https://api.qonversion.io/"))

        XCTAssertEqual(request.url?.absoluteString, "https://api.qonversion.io/v4/users/user%201/offerings")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
    }

    // MARK: - Service

    func testServiceSendsGetOfferingsRequestAndReturnsProcessorResult() async throws {
        let processor = MockRequestProcessor()
        let config = InternalConfig(userId: "QON_offerings_user")
        let service = ProductsService(requestProcessor: processor, internalConfig: config)
        let stubOffering: Qonversion.Offering = makeOffering(id: "main_paywall", tag: .main, productIds: ["pro"])
        processor.results = [ListEnvelope<Qonversion.Offering>(data: [stubOffering])]

        let offerings: [Qonversion.Offering] = try await service.offerings(userId: "user_abc")

        XCTAssertEqual(processor.processedRequests, [Request.getOfferings(userId: "user_abc")])
        XCTAssertEqual(offerings.map(\.id), ["main_paywall"])
    }

    func testServiceWrapsProcessorErrorIntoOfferingsLoadingFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = ProductsService(requestProcessor: processor, internalConfig: InternalConfig(userId: "QON_offerings_user"))

        do {
            _ = try await service.offerings(userId: "user_abc")
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .offeringsLoadingFailed)
            XCTAssertEqual(error.error as? MockError, .stubbed)
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    // MARK: - Manager

    private var productsService: MockProductsService!
    private var storeKitFacade: MockStoreKitFacade!
    private var localStorage: MockLocalStorage!
    private var fallbackService: MockFallbackService!
    private var userManager: MockUserManager!
    private var config: InternalConfig!
    private var manager: ProductsManager!

    override func setUp() {
        super.setUp()
        productsService = MockProductsService()
        storeKitFacade = MockStoreKitFacade()
        localStorage = MockLocalStorage()
        fallbackService = MockFallbackService()
        userManager = MockUserManager()
        userManager.user = Qonversion.User(id: "user_abc")
        config = InternalConfig(userId: "user_abc")
        manager = ProductsManager(
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: localStorage,
            fallbackService: fallbackService,
            userManager: userManager,
            userIdProvider: config,
            logger: LoggerWrapper()
        )
    }

    override func tearDown() {
        manager = nil
        config = nil
        userManager = nil
        fallbackService = nil
        localStorage = nil
        storeKitFacade = nil
        productsService = nil
        super.tearDown()
    }

    func testOfferingsWaitsForTheUserGateAndPassesTheCurrentUid() async throws {
        productsService.offeringsResult = [makeOffering(id: "main_paywall", tag: .main)]

        _ = try await manager.offerings()

        XCTAssertEqual(userManager.obtainUserCallsCount, 1)
        XCTAssertEqual(productsService.offeringsRequestedUserIds, ["user_abc"])
    }

    func testOfferingsUserGateErrorPropagatesWithoutServiceCall() async {
        userManager.error = MockError.stubbed

        do {
            _ = try await manager.offerings()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? MockError, .stubbed)
        }
        XCTAssertTrue(productsService.offeringsRequestedUserIds.isEmpty)
    }

    func testOfferingsServiceErrorPropagatesAndIsNotCached() async throws {
        productsService.offeringsError = MockError.stubbed

        do {
            _ = try await manager.offerings()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? MockError, .stubbed)
        }

        productsService.offeringsError = nil
        productsService.offeringsResult = [makeOffering(id: "main_paywall", tag: .main)]

        let offerings: Qonversion.Offerings = try await manager.offerings()

        XCTAssertEqual(offerings.main?.id, "main_paywall")
        XCTAssertEqual(productsService.offeringsCallsCount, 2)
    }

    func testOfferingsEnrichesAllProductsWithASingleStoreRequest() async throws {
        productsService.offeringsResult = [
            makeOffering(id: "main_paywall", tag: .main, productIds: ["pro"]),
            makeOffering(id: "secondary", tag: .none, productIds: ["lite"]),
        ]
        let skProduct = SKProduct()
        let proWrapper = StoreProductWrapper(_product: nil, oldProduct: skProduct)
        storeKitFacade.productsResult = [proWrapper]

        _ = try await manager.offerings()

        XCTAssertEqual(storeKitFacade.requestedProductIds, [["store_pro", "store_lite"]])
    }

    func testOfferingsKeepsUnmatchedProductsUnenriched() async throws {
        // The paywall composition is backend-driven: a product the store does
        // not know stays in the offering, just without store data.
        productsService.offeringsResult = [makeOffering(id: "main_paywall", tag: .main, productIds: ["pro", "web_only"])]
        storeKitFacade.productsError = MockError.stubbed

        let offerings: Qonversion.Offerings = try await manager.offerings()

        XCTAssertEqual(offerings.main?.products.map(\.qonversionId), ["pro", "web_only"])
        XCTAssertEqual(offerings.main?.products.filter(\.isStoreProductLinked).count, 0)
    }

    func testOfferingsAreCachedInMemory() async throws {
        productsService.offeringsResult = [makeOffering(id: "main_paywall", tag: .main)]

        _ = try await manager.offerings()
        let second: Qonversion.Offerings = try await manager.offerings()

        XCTAssertEqual(second.main?.id, "main_paywall")
        XCTAssertEqual(productsService.offeringsCallsCount, 1)
    }

    func testUserChangeClearsTheOfferingsCache() async throws {
        // Offerings are personalized (experiments) — the next user must not
        // see the previous user's paywall.
        productsService.offeringsResult = [makeOffering(id: "main_paywall", tag: .main)]
        _ = try await manager.offerings()

        manager.userDidChange()
        _ = try await manager.offerings()

        XCTAssertEqual(productsService.offeringsCallsCount, 2)
    }

    // MARK: - Trial / intro eligibility

    private func makeProduct(qonversionId: String, storeId: String) -> Qonversion.Product {
        return Qonversion.Product(qonversionId: qonversionId, storeId: storeId, offeringId: nil)
    }

    private func makeIntroOffer() -> Qonversion.Product.SubscriptionOffer {
        let period = Qonversion.Product.SubscriptionPeriod(unit: .week, value: 1)
        return Qonversion.Product.SubscriptionOffer(
            id: nil,
            type: .introductory,
            price: 0,
            displayPrice: "0",
            period: period,
            periodCount: 1,
            paymentMode: .freeTrial
        )
    }

    func testEligibilityIsUnknownForUnknownProductId() async throws {
        manager.loadedProducts = [makeProduct(qonversionId: "pro", storeId: "store_pro")]

        let result: [String: Qonversion.IntroEligibilityStatus] = try await manager.checkTrialIntroEligibility(productIds: ["missing"])

        XCTAssertEqual(result, ["missing": .unknown])
    }

    func testEligibilityIsUnknownForProductWithoutStoreLink() async throws {
        manager.loadedProducts = [makeProduct(qonversionId: "pro", storeId: "store_pro")]

        let result: [String: Qonversion.IntroEligibilityStatus] = try await manager.checkTrialIntroEligibility(productIds: ["pro"])

        XCTAssertEqual(result, ["pro": .unknown])
    }

    func testEligibilityIsNonIntroProductForLinkedProductWithoutIntroOffer() async throws {
        var product: Qonversion.Product = makeProduct(qonversionId: "pro", storeId: "store_pro")
        product.skProduct = SKProduct()
        manager.loadedProducts = [product]

        let result: [String: Qonversion.IntroEligibilityStatus] = try await manager.checkTrialIntroEligibility(productIds: ["pro"])

        XCTAssertEqual(result, ["pro": .nonIntroOrTrialProduct])
    }

    func testEligibilityComesFromTheStoreForIntroProducts() async throws {
        var eligible: Qonversion.Product = makeProduct(qonversionId: "pro", storeId: "store_pro")
        eligible.skProduct = SKProduct()
        let period = Qonversion.Product.SubscriptionPeriod(unit: .month, value: 1)
        eligible.subscription = Qonversion.Product.SubscriptionInfo(subscriptionGroupId: "group", subscriptionPeriod: period, introductoryOffer: makeIntroOffer())

        var ineligible: Qonversion.Product = makeProduct(qonversionId: "lite", storeId: "store_lite")
        ineligible.skProduct = SKProduct()
        ineligible.subscription = Qonversion.Product.SubscriptionInfo(subscriptionGroupId: "group", subscriptionPeriod: period, introductoryOffer: makeIntroOffer())

        manager.loadedProducts = [eligible, ineligible]
        storeKitFacade.introOfferEligibilityResults = ["store_pro": true, "store_lite": false]

        let result: [String: Qonversion.IntroEligibilityStatus] = try await manager.checkTrialIntroEligibility(productIds: ["pro", "lite"])

        XCTAssertEqual(result, ["pro": .eligible, "lite": .ineligible])
        XCTAssertEqual(storeKitFacade.eligibilityRequestedStoreIds.sorted(), ["store_lite", "store_pro"])
    }

    func testEligibilityIsUnknownWhenTheStoreCannotAnswer() async throws {
        var product: Qonversion.Product = makeProduct(qonversionId: "pro", storeId: "store_pro")
        product.skProduct = SKProduct()
        let period = Qonversion.Product.SubscriptionPeriod(unit: .month, value: 1)
        product.subscription = Qonversion.Product.SubscriptionInfo(subscriptionGroupId: "group", subscriptionPeriod: period, introductoryOffer: makeIntroOffer())
        manager.loadedProducts = [product]
        // No stubbed eligibility — the facade answers nil.

        let result: [String: Qonversion.IntroEligibilityStatus] = try await manager.checkTrialIntroEligibility(productIds: ["pro"])

        XCTAssertEqual(result, ["pro": .unknown])
    }
}
