//
//  IntroEligibilityTests.swift
//  QonversionUnitTests
//
//  Trial/intro eligibility is resolved on the device: products without an
//  introductory offer are non-intro, the rest are answered by StoreKit 2
//  from the subscription group history.
//

import XCTest
import StoreKit
@testable import Qonversion

final class IntroEligibilityTests: XCTestCase {

    private var productsService: MockProductsService!
    private var storeKitFacade: MockStoreKitFacade!
    private var localStorage: MockLocalStorage!
    private var fallbackService: MockFallbackService!
    private var manager: ProductsManager!

    override func setUp() {
        super.setUp()
        productsService = MockProductsService()
        storeKitFacade = MockStoreKitFacade()
        localStorage = MockLocalStorage()
        fallbackService = MockFallbackService()
        manager = ProductsManager(
            apiKey: "test_api_key",
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: localStorage,
            fallbackService: fallbackService,
            logger: LoggerWrapper()
        )
    }

    override func tearDown() {
        manager = nil
        fallbackService = nil
        localStorage = nil
        storeKitFacade = nil
        productsService = nil
        super.tearDown()
    }

    // MARK: - Helpers

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

    // MARK: - Tests

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
        product._storeProduct = FakeLinkedStoreProduct()
        manager.loadedProducts = [product]

        let result: [String: Qonversion.IntroEligibilityStatus] = try await manager.checkTrialIntroEligibility(productIds: ["pro"])

        XCTAssertEqual(result, ["pro": .nonIntroOrTrialProduct])
    }

    func testEligibilityComesFromTheStoreForIntroProducts() async throws {
        let period = Qonversion.Product.SubscriptionPeriod(unit: .month, value: 1)

        var eligible: Qonversion.Product = makeProduct(qonversionId: "pro", storeId: "store_pro")
        eligible._storeProduct = FakeLinkedStoreProduct()
        eligible.subscription = Qonversion.Product.SubscriptionInfo(subscriptionGroupId: "group", subscriptionPeriod: period, introductoryOffer: makeIntroOffer())

        var ineligible: Qonversion.Product = makeProduct(qonversionId: "lite", storeId: "store_lite")
        ineligible._storeProduct = FakeLinkedStoreProduct()
        ineligible.subscription = Qonversion.Product.SubscriptionInfo(subscriptionGroupId: "group", subscriptionPeriod: period, introductoryOffer: makeIntroOffer())

        manager.loadedProducts = [eligible, ineligible]
        storeKitFacade.introOfferEligibilityResults = ["store_pro": true, "store_lite": false]

        let result: [String: Qonversion.IntroEligibilityStatus] = try await manager.checkTrialIntroEligibility(productIds: ["pro", "lite"])

        XCTAssertEqual(result, ["pro": .eligible, "lite": .ineligible])
        XCTAssertEqual(storeKitFacade.eligibilityRequestedStoreIds.sorted(), ["store_lite", "store_pro"])
    }

    func testEligibilityIsUnknownWhenTheStoreCannotAnswer() async throws {
        var product: Qonversion.Product = makeProduct(qonversionId: "pro", storeId: "store_pro")
        product._storeProduct = FakeLinkedStoreProduct()
        let period = Qonversion.Product.SubscriptionPeriod(unit: .month, value: 1)
        product.subscription = Qonversion.Product.SubscriptionInfo(subscriptionGroupId: "group", subscriptionPeriod: period, introductoryOffer: makeIntroOffer())
        manager.loadedProducts = [product]
        // No stubbed eligibility — the facade answers nil.

        let result: [String: Qonversion.IntroEligibilityStatus] = try await manager.checkTrialIntroEligibility(productIds: ["pro"])

        XCTAssertEqual(result, ["pro": .unknown])
    }
}

/// Real StoreKit.Product values cannot be constructed in unit tests; linking
/// is asserted through the internal seam the enrichment writes to.
private final class FakeLinkedStoreProduct { }
