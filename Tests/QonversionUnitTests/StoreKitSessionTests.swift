//
//  StoreKitSessionTests.swift
//  QonversionUnitTests
//
//  Layer 2 integration: the REAL object graph over the REAL StoreKit.
//  Only the HTTP boundary is stubbed (StubNetworkProvider, shared with the
//  Layer 1 IntegrationTests); StoreKit is not stubbed at all — the production
//  StoreKitWrapper/StoreKitFacade talk to an SKTestSession configured from the
//  bundled Qonversion.storekit file.
//
//  Environment honesty: StoreKit testing needs an application host the
//  storekitagent accepts. Under a plain `swift test` run there is none — the
//  agent rejects the configuration ("Error saving configuration file",
//  SKInternalErrorDomain 3) and no product loads. Every test therefore probes
//  the environment first and XCTSkips when it is unusable: the suite must stay
//  green everywhere and must never pretend a store round trip happened.
//
//  To actually execute this layer, run it from a test target with a host
//  application — an iOS/tvOS simulator app, or a macOS app with the regular
//  activation policy and a window (an accessory app without one makes
//  StoreKit.Product.purchase() fail with StoreKitError.unknown). All seven
//  tests were verified green that way; they skip under `swift test`.
//

#if canImport(StoreKitTest)

import XCTest
import StoreKit
import StoreKitTest
@testable import Qonversion

// MARK: - Store ids of the bundled configuration

private enum StoreIds {
    static let monthly: String = "test.monthly"
    static let yearly: String = "test.yearly"
    static let consumable: String = "test.consumable"
    static let lifetime: String = "test.lifetime"
}

private enum QonversionIds {
    static let monthly: String = "monthly"
    static let yearly: String = "yearly"
    static let consumable: String = "consumable"
    static let lifetime: String = "lifetime"
    static let premium: String = "premium"
    static let forever: String = "forever"
}

// MARK: - The world under test

/// The full real object graph with the HTTP boundary stubbed and StoreKit
/// left alone — `storeKitWrapperOverride` is deliberately NOT set, so the
/// production StoreKitWrapper runs against the active SKTestSession.
private final class StoreWorld {

    let assembly: QonversionAssembly
    let network: StubNetworkProvider
    let userDefaults: UserDefaults

    let storeKitFacade: StoreKitFacade
    let productsManager: ProductsManagerInterface
    let purchasesManager: PurchasesManagerInterface
    let entitlementsManager: EntitlementsManagerInterface

    init(userDefaults: UserDefaults, launchMode: Qonversion.LaunchMode = .subscriptionManagement) {
        self.userDefaults = userDefaults
        let network = StubNetworkProvider()
        self.network = network

        let assembly = QonversionAssembly(apiKey: "storekit-session-key", userDefaults: userDefaults, launchMode: launchMode)
        assembly.servicesAssembly.networkProviderOverride = network
        self.assembly = assembly

        storeKitFacade = assembly.servicesAssembly.storeKitFacade()
        productsManager = assembly.productsManager()
        entitlementsManager = assembly.entitlementsManager()
        purchasesManager = assembly.purchasesManager()
    }

    var uid: String { userDefaults.string(forKey: "qonversion.keys.userId") ?? "" }

    /// Backend catalog referencing the store ids of the bundled configuration
    /// plus the routes every purchase flow touches.
    func stubBackend() {
        let userBody: String = #"{"id": "\#(uid)", "created_at": "2026-07-27T10:00:00Z", "environment": "prod"}"#
        network.stub("POST", "/v4/users", body: userBody)
        network.stub("GET", "/v4/users/*", body: userBody)

        let productsBody: String = """
        {"object": "list", "data": [
            {"id": "\(QonversionIds.monthly)", "apple_product_id": "\(StoreIds.monthly)"},
            {"id": "\(QonversionIds.yearly)", "apple_product_id": "\(StoreIds.yearly)"},
            {"id": "\(QonversionIds.consumable)", "apple_product_id": "\(StoreIds.consumable)"},
            {"id": "\(QonversionIds.lifetime)", "apple_product_id": "\(StoreIds.lifetime)"}
        ]}
        """
        network.stub("GET", "/v4/products", body: productsBody)

        let definitionsBody: String = """
        {"object": "list", "data": [
            {"id": "\(QonversionIds.premium)", "product_ids": ["\(QonversionIds.monthly)", "\(QonversionIds.yearly)"]},
            {"id": "\(QonversionIds.forever)", "product_ids": ["\(QonversionIds.lifetime)"]}
        ]}
        """
        network.stub("GET", "/v4/entitlements", body: definitionsBody)

        network.stub("POST", "/v4/users/*/purchases", body: #"{"object": "purchase"}"#)
        network.stub("GET", "/v4/users/*/entitlements", body: #"{"object": "list", "data": [{"id": "premium", "is_active": true}]}"#)
    }
}

// MARK: - Tests

final class StoreKitSessionTests: XCTestCase {

    private var session: SKTestSession!
    private var world: StoreWorld!

    override func setUp() async throws {
        try await super.setUp()

        let preparedSession: SKTestSession? = await Self.makeSessionIfUsable()
        guard let preparedSession else {
            throw XCTSkip("StoreKit testing is unavailable in this environment: the store returned no products for the bundled configuration. StoreKitTest needs a test host the storekitagent accepts, which a plain `swift test` run does not provide.")
        }
        session = preparedSession

        let defaults: UserDefaults = TestDefaults.makeIsolated()
        world = StoreWorld(userDefaults: defaults)
        world.stubBackend()
    }

    override func tearDown() async throws {
        world?.storeKitFacade.stopObservingTransactionUpdates()
        world = nil
        session?.clearTransactions()
        session = nil
        try await super.tearDown()
    }

    // MARK: - a. real product loading and enrichment

    func testRealStoreProductsEnrichTheBackendCatalog() async throws {
        let products: [Qonversion.Product] = try await world.productsManager.products()

        XCTAssertEqual(products.count, 4)
        XCTAssertEqual(world.network.recordedRequests("GET", "/v4/products").count, 1)

        let monthly: Qonversion.Product = try XCTUnwrap(products.first { $0.qonversionId == QonversionIds.monthly })
        XCTAssertTrue(monthly.isStoreProductLinked, "the real StoreKit product must be attached to the backend product")
        XCTAssertEqual(monthly.storeProduct?.id, StoreIds.monthly)
        XCTAssertEqual(monthly.type, .autoRenewable)
        let expectedMonthlyPrice: Decimal = Decimal(string: "9.99") ?? 0
        XCTAssertEqual(monthly.price, expectedMonthlyPrice)
        let monthlyDisplayPrice: String = try XCTUnwrap(monthly.displayPrice)
        XCTAssertTrue(monthlyDisplayPrice.contains("9.99"), "unexpected display price: " + monthlyDisplayPrice)

        let monthlySubscription: Qonversion.Product.SubscriptionInfo = try XCTUnwrap(monthly.subscription)
        XCTAssertEqual(monthlySubscription.subscriptionPeriod.unit, .month)
        XCTAssertEqual(monthlySubscription.subscriptionPeriod.value, 1)
        let intro: Qonversion.Product.SubscriptionOffer = try XCTUnwrap(monthlySubscription.introductoryOffer, "the configured free trial must survive the enrichment")
        XCTAssertEqual(intro.type, .introductory)
        XCTAssertEqual(intro.paymentMode, .freeTrial)
        XCTAssertEqual(intro.period.unit, .week)
        XCTAssertEqual(intro.period.value, 1)

        let yearly: Qonversion.Product = try XCTUnwrap(products.first { $0.qonversionId == QonversionIds.yearly })
        let yearlySubscription: Qonversion.Product.SubscriptionInfo = try XCTUnwrap(yearly.subscription)
        XCTAssertEqual(yearlySubscription.subscriptionPeriod.unit, .year)
        XCTAssertNil(yearlySubscription.introductoryOffer)
        XCTAssertEqual(yearlySubscription.subscriptionGroupId, monthlySubscription.subscriptionGroupId)

        let consumable: Qonversion.Product = try XCTUnwrap(products.first { $0.qonversionId == QonversionIds.consumable })
        XCTAssertEqual(consumable.type, .consumable)
        XCTAssertNil(consumable.subscription)

        let lifetime: Qonversion.Product = try XCTUnwrap(products.first { $0.qonversionId == QonversionIds.lifetime })
        XCTAssertEqual(lifetime.type, .nonConsumable)
        XCTAssertNil(lifetime.subscription)
    }

    // MARK: - b. purchase end to end

    func testPurchaseReportsTheSignedJwsAndFinishesTheTransaction() async throws {
        let monthly: Qonversion.Product = try await loadProduct(QonversionIds.monthly)

        let result: Qonversion.PurchaseResult = try await world.purchasesManager.purchase(monthly, options: nil)
        let transaction: Qonversion.Transaction = result.transaction

        XCTAssertEqual(transaction.productId, StoreIds.monthly)
        let transactionId: String = try XCTUnwrap(transaction.id)
        let jws: String = try XCTUnwrap(transaction.jws, "a verified StoreKit 2 purchase must carry its signed representation")
        XCTAssertEqual(jws.split(separator: ".").count, 3, "the jws must be the three-part signed payload")

        let report: URLRequest = try XCTUnwrap(world.network.recordedRequests("POST", "/v4/users/*/purchases").first)
        XCTAssertEqual(report.value(forHTTPHeaderField: "Trigger"), "Purchase")
        let body: [String: Any] = try XCTUnwrap(report.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let storeData: [String: Any] = try XCTUnwrap(body["store_data"] as? [String: Any])
        XCTAssertEqual(storeData["receipt"] as? String, jws, "the signed transaction must travel in the receipt slot")
        XCTAssertEqual(storeData["transaction_id"] as? String, transactionId)
        XCTAssertEqual(storeData["product_id"] as? String, StoreIds.monthly)

        // Subscription management owns the transaction lifecycle: the store
        // must consider it finished after the backend answered 200.
        let facade: StoreKitFacade = world.storeKitFacade
        await waitUntilAsync {
            let pending: [Qonversion.Transaction] = await facade.unfinishedTransactions()
            return !pending.contains { $0.id == transactionId }
        }
        let unfinished: [Qonversion.Transaction] = await facade.unfinishedTransactions()
        XCTAssertFalse(unfinished.contains { $0.id == transactionId }, "a reported purchase must be finished with the store")
    }

    // MARK: - c. the signed expiration wins over the local approximation

    func testEntitlementExpirationComesFromTheSignedTransaction() async throws {
        // The backend grants nothing here: a cached remote entitlement would
        // win the merge and hide the locally calculated expiration.
        world.network.stub("GET", "/v4/users/*/entitlements", body: #"{"object": "list", "data": []}"#)
        await world.productsManager.loadProductPermissions()
        let monthly: Qonversion.Product = try await loadProduct(QonversionIds.monthly)

        let result: Qonversion.PurchaseResult = try await world.purchasesManager.purchase(monthly, options: nil)
        let transaction: Qonversion.Transaction = result.transaction

        let signedExpiration: Date = try XCTUnwrap(transaction.expirationDate, "the store signs the expiration of a subscription transaction")
        let purchaseDate: Date = try XCTUnwrap(transaction.purchaseDate)

        // The calculator must return the signed date verbatim...
        let calculated: Date = try XCTUnwrap(EntitlementsCalculator.expirationDate(for: transaction, product: monthly))
        XCTAssertEqual(calculated, signedExpiration)

        // ...and NOT the day-based approximation of the product period. The
        // purchase runs the one week free trial, so the approximated thirty
        // days of a monthly product would overstate the access by weeks.
        let monthApproximation: Date = purchaseDate.addingTimeInterval(30 * 24 * 60 * 60)
        XCTAssertNotEqual(calculated, monthApproximation)
        XCTAssertLessThan(calculated, monthApproximation, "the trial expires long before the approximated monthly period")

        // The same date reaches the entitlement the SDK hands to the host.
        let entitlements: [String: Qonversion.Entitlement] = await world.entitlementsManager.localFallbackEntitlements(for: [transaction])
        let premium: Qonversion.Entitlement = try XCTUnwrap(entitlements[QonversionIds.premium])
        XCTAssertTrue(premium.active)
        XCTAssertEqual(premium.expirationDate, signedExpiration)
        XCTAssertEqual(premium.productId, QonversionIds.monthly)
    }

    // MARK: - d. intro eligibility before and after the purchase

    func testIntroEligibilityFlipsAfterTheTrialIsConsumed() async throws {
        let before: [String: Qonversion.IntroEligibilityStatus] = try await world.productsManager.checkTrialIntroEligibility(productIds: [QonversionIds.monthly, QonversionIds.yearly, QonversionIds.lifetime])

        XCTAssertEqual(before[QonversionIds.monthly], .eligible, "a fresh store account is eligible for the configured trial")
        XCTAssertEqual(before[QonversionIds.yearly], .nonIntroOrTrialProduct, "the yearly product has no introductory offer")
        XCTAssertEqual(before[QonversionIds.lifetime], .nonIntroOrTrialProduct)

        let monthly: Qonversion.Product = try await loadProduct(QonversionIds.monthly)
        _ = try await world.purchasesManager.purchase(monthly, options: nil)

        // The store updates the eligibility asynchronously after the purchase.
        let manager: ProductsManagerInterface = world.productsManager
        await waitUntilAsync {
            let statuses: [String: Qonversion.IntroEligibilityStatus] = (try? await manager.checkTrialIntroEligibility(productIds: [QonversionIds.monthly])) ?? [:]
            return statuses[QonversionIds.monthly] == .ineligible
        }

        let after: [String: Qonversion.IntroEligibilityStatus] = try await world.productsManager.checkTrialIntroEligibility(productIds: [QonversionIds.monthly])
        XCTAssertEqual(after[QonversionIds.monthly], .ineligible, "the consumed trial makes the user ineligible")
    }

    // MARK: - e. restore

    func testRestoreReturnsThePurchasedTransactions() async throws {
        let monthly: Qonversion.Product = try await loadProduct(QonversionIds.monthly)
        let result: Qonversion.PurchaseResult = try await world.purchasesManager.purchase(monthly, options: nil)
        let purchasedId: String = try XCTUnwrap(result.transaction.id)

        // The store side of restore: a real AppStore.sync() plus the verified
        // transactions the production wrapper maps.
        let restored: [Qonversion.Transaction] = try await world.storeKitFacade.restore()
        XCTAssertTrue(restored.contains { $0.id == purchasedId }, "restore must return the purchased transaction")
        let restoredMonthly: Qonversion.Transaction = try XCTUnwrap(restored.first { $0.productId == StoreIds.monthly })
        XCTAssertNotNil(restoredMonthly.jws, "a restored transaction keeps its signed proof")

        // The manager level answers with the entitlements of the restore.
        let entitlements: [String: Qonversion.Entitlement] = try await world.purchasesManager.restore()
        XCTAssertEqual(entitlements[QonversionIds.premium]?.active, true)
    }

    // MARK: - f. currentEntitlements

    func testCurrentEntitlementsReflectTheActivePurchase() async throws {
        // As above: an empty remote answer keeps the local calculation from
        // being shadowed by a cached backend entitlement.
        world.network.stub("GET", "/v4/users/*/entitlements", body: #"{"object": "list", "data": []}"#)
        await world.productsManager.loadProductPermissions()
        let monthly: Qonversion.Product = try await loadProduct(QonversionIds.monthly)
        let result: Qonversion.PurchaseResult = try await world.purchasesManager.purchase(monthly, options: nil)
        let purchasedId: String = try XCTUnwrap(result.transaction.id)

        // The store publishes the entitlement asynchronously after the purchase.
        let facade: StoreKitFacade = world.storeKitFacade
        await waitUntilAsync {
            let entitled: [Qonversion.Transaction] = await facade.currentEntitlements()
            return entitled.contains { $0.productId == StoreIds.monthly }
        }
        let current: [Qonversion.Transaction] = await facade.currentEntitlements()
        let active: Qonversion.Transaction = try XCTUnwrap(current.first { $0.productId == StoreIds.monthly }, "the active subscription must appear in the store entitlements")
        XCTAssertEqual(active.id, purchasedId)

        // The offline path consults exactly those store entitlements: with the
        // backend unreachable the SDK must still report the purchase locally.
        let transportError: URLError = URLError(.notConnectedToInternet)
        world.network.stub("GET", "/v4/users/*/entitlements", transportError: transportError)
        let entitlements: [String: Qonversion.Entitlement] = try await world.entitlementsManager.entitlements()

        let premium: Qonversion.Entitlement = try XCTUnwrap(entitlements[QonversionIds.premium], "the real store entitlement must survive the backend outage")
        XCTAssertTrue(premium.active)
        XCTAssertEqual(premium.productId, QonversionIds.monthly)
    }

    // MARK: - g. out-of-band transaction updates

    func testOutOfBandPurchaseReachesTheTransactionUpdatesPath() async throws {
        guard #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *) else {
            throw XCTSkip("SKTestSession.buyProduct(identifier:options:) requires iOS 17 / macOS 14 / tvOS 17 / watchOS 10")
        }

        // Warm the catalog so the local calculation has products to work with.
        _ = try await world.productsManager.products()
        world.purchasesManager.startObservingTransactions()

        // The listener attaches on its own long-lived task. This is the one
        // place a wait cannot be expressed as a poll on an observable effect:
        // it settles the subscription BEFORE the trigger. Every assertion
        // below still polls with a deadline.
        try? await Task.sleep(nanoseconds: 300_000_000)

        let network: StubNetworkProvider = world.network
        let outOfBand: StoreKit.Transaction = try await session.buyProduct(identifier: StoreIds.yearly)
        let outOfBandId: String = String(outOfBand.id)

        await waitUntil {
            return Self.report(for: outOfBandId, in: network.recordedRequests("POST", "/v4/users/*/purchases")) != nil
        }

        let reports: [URLRequest] = world.network.recordedRequests("POST", "/v4/users/*/purchases")
        let matching: URLRequest? = Self.report(for: outOfBandId, in: reports)
        let report: URLRequest = try XCTUnwrap(matching, "the observed transaction must reach the SDK's transaction updates path")
        XCTAssertEqual(report.value(forHTTPHeaderField: "Trigger"), "Purchase")
        let body: [String: Any] = try XCTUnwrap(report.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let storeData: [String: Any] = try XCTUnwrap(body["store_data"] as? [String: Any])
        XCTAssertEqual(storeData["product_id"] as? String, StoreIds.yearly)
        let receipt: String = try XCTUnwrap(storeData["receipt"] as? String)
        XCTAssertEqual(receipt.split(separator: ".").count, 3)

        // Subscription management finishes an observed transaction after the
        // backend confirms it.
        let facade: StoreKitFacade = world.storeKitFacade
        await waitUntilAsync {
            let pending: [Qonversion.Transaction] = await facade.unfinishedTransactions()
            return !pending.contains { $0.id == outOfBandId }
        }
        let unfinished: [Qonversion.Transaction] = await facade.unfinishedTransactions()
        XCTAssertFalse(unfinished.contains { $0.id == outOfBandId })
    }
}

// MARK: - Helpers

private extension StoreKitSessionTests {

    /// Builds a session over the bundled configuration and proves the store
    /// actually answers with the configured products. Returns nil when the
    /// environment cannot run StoreKit tests at all.
    static func makeSessionIfUsable() async -> SKTestSession? {
        guard let url: URL = Bundle.module.url(forResource: "Qonversion", withExtension: "storekit") else { return nil }
        guard let session: SKTestSession = try? SKTestSession(contentsOf: url) else { return nil }

        session.disableDialogs = true
        session.clearTransactions()

        let ids: Set<String> = [StoreIds.monthly, StoreIds.yearly, StoreIds.consumable, StoreIds.lifetime]
        let loaded: [StoreKit.Product] = (try? await StoreKit.Product.products(for: ids)) ?? []
        guard loaded.count == ids.count else { return nil }

        return session
    }

    func loadProduct(_ qonversionId: String) async throws -> Qonversion.Product {
        let products: [Qonversion.Product] = try await world.productsManager.products()

        return try XCTUnwrap(products.first { $0.qonversionId == qonversionId })
    }

    /// The purchase report of the given store transaction id, if the stub
    /// recorded one.
    static func report(for transactionId: String, in requests: [URLRequest]) -> URLRequest? {
        return requests.first { request in
            let body: [String: Any]? = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let storeData: [String: Any]? = body?["store_data"] as? [String: Any]
            return storeData?["transaction_id"] as? String == transactionId
        }
    }

    func waitUntil(timeout: TimeInterval = 5.0, _ condition: () -> Bool) async {
        let deadline: Date = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func waitUntilAsync(timeout: TimeInterval = 5.0, _ condition: () async -> Bool) async {
        let deadline: Date = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

#endif
