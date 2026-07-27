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
//  Environment honesty, and only where it is honest. The probe in setUp
//  separates three outcomes and never collapses them:
//    - the resource is missing, unreadable or the store answers with a product
//      set that does not match the configuration -> FAIL (a packaging or
//      configuration bug must not hide behind a skip);
//    - the store is not there at all (no products, the agent rejected the
//      configuration, or it never answered) -> SKIP with a distinct message;
//    - QONVERSION_REQUIRE_STOREKIT set -> never skip, fail instead. Set it in
//      any run that is supposed to exercise this layer for real.
//
//  Under a plain `swift test` run there is no application host the
//  storekitagent accepts: it rejects the configuration ("Error saving
//  configuration file", SKInternalErrorDomain 3) and no product loads, so this
//  layer skips. To execute it, run from a test target with a host application
//  — an iOS/tvOS simulator app, or a macOS app with the regular activation
//  policy and a window (an accessory app without one makes
//  StoreKit.Product.purchase() fail with StoreKitError.unknown).
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

    static let all: Set<String> = [monthly, yearly, consumable, lifetime]
}

private enum QonversionIds {
    static let monthly: String = "monthly"
    static let yearly: String = "yearly"
    static let consumable: String = "consumable"
    static let lifetime: String = "lifetime"
    static let premium: String = "premium"
    static let forever: String = "forever"
}

// MARK: - Environment probe outcome

/// What the store answered before any test ran.
private enum StoreKitProbe {

    /// The configuration is live and complete.
    case ready(SKTestSession)

    /// The resource or the configuration itself is wrong — always a failure.
    case broken(String)

    /// No store to talk to in this process — a skip, unless the run demands one.
    case unavailable(String)
}

/// Thrown to abort setUp after the failure has already been recorded.
private struct StoreKitEnvironmentFailure: Error, CustomStringConvertible {
    let description: String
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
            {"id": "\(QonversionIds.forever)", "product_ids": ["\(QonversionIds.lifetime)", "\(QonversionIds.consumable)"]}
        ]}
        """
        network.stub("GET", "/v4/entitlements", body: definitionsBody)

        network.stub("POST", "/v4/users/*/purchases", body: #"{"object": "purchase"}"#)
        network.stub("GET", "/v4/users/*/entitlements", body: #"{"object": "list", "data": [{"id": "premium", "is_active": true}]}"#)
    }

    /// The backend grants nothing: a cached remote entitlement would win the
    /// merge and hide whatever the local calculation produced.
    func stubEmptyRemoteEntitlements() {
        network.stub("GET", "/v4/users/*/entitlements", body: #"{"object": "list", "data": []}"#)
    }

    /// Warms the catalog and the product -> entitlements mapping the local
    /// calculation needs.
    func warmCatalog() async throws {
        await productsManager.loadProductPermissions()
        _ = try await productsManager.products()
    }
}

// MARK: - Tests

final class StoreKitSessionTests: XCTestCase {

    private var session: SKTestSession!
    private var world: StoreWorld!
    private var probe: StoreKitProbe!

    override func setUp() async throws {
        try await super.setUp()

        // The verdict is recorded here but acted on inside each test: an error
        // thrown from setUp is reported as skipped AND failed, which is exactly
        // the ambiguity this guard exists to remove.
        let outcome: StoreKitProbe = await Self.probeStoreKitEnvironment()
        probe = outcome

        guard case .ready(let preparedSession) = outcome else { return }
        session = preparedSession

        let defaults: UserDefaults = TestDefaults.makeIsolated()
        world = StoreWorld(userDefaults: defaults)
        world.stubBackend()
    }

    /// A wrong configuration fails, a missing store skips, and a run that
    /// demands StoreKit never skips.
    private func requireStoreKit() throws {
        switch probe {
        case .ready:
            return

        case .broken(let reason):
            XCTFail("The StoreKit test configuration is unusable: " + reason)
            throw StoreKitEnvironmentFailure(description: "unusable StoreKit test configuration, see the failure above")

        case .unavailable(let reason):
            guard !Self.storeKitIsRequired else {
                XCTFail("\(Self.requireStoreKitVariable) is set, so this run must exercise real StoreKit, but " + reason)
                throw StoreKitEnvironmentFailure(description: "StoreKit testing required but unavailable, see the failure above")
            }
            throw XCTSkip("StoreKit testing is unavailable in this process: " + reason + " StoreKitTest needs a host application the storekitagent accepts, which a plain `swift test` run does not provide. Set \(Self.requireStoreKitVariable) to turn this skip into a failure.")

        case .none:
            XCTFail("The StoreKit environment probe did not run")
            throw StoreKitEnvironmentFailure(description: "missing StoreKit environment probe")
        }
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
        try requireStoreKit()

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
        try requireStoreKit()

        let monthly: Qonversion.Product = try await loadProduct(QonversionIds.monthly)

        let result: Qonversion.PurchaseResult = try await world.purchasesManager.purchase(monthly, options: nil)
        let transaction: Qonversion.Transaction = result.transaction

        XCTAssertEqual(transaction.productId, StoreIds.monthly)
        let transactionId: String = try XCTUnwrap(transaction.id)
        let jws: String = try XCTUnwrap(transaction.jws, "a verified StoreKit 2 purchase must carry its signed representation")

        // The jws must be THIS transaction, not merely a well-shaped string.
        let payload: [String: Any] = try XCTUnwrap(Self.jwsPayload(jws), "the jws must carry a decodable payload segment")
        XCTAssertEqual(payload["transactionId"] as? String, transactionId, "the signed payload must describe the purchased transaction")
        XCTAssertEqual(payload["productId"] as? String, StoreIds.monthly)

        let report: URLRequest = try XCTUnwrap(world.network.recordedRequests("POST", "/v4/users/*/purchases").first)
        XCTAssertEqual(report.value(forHTTPHeaderField: "Trigger"), "Purchase")
        let body: [String: Any] = try XCTUnwrap(report.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let storeData: [String: Any] = try XCTUnwrap(body["store_data"] as? [String: Any])
        XCTAssertEqual(storeData["receipt"] as? String, jws, "the signed transaction must travel in the receipt slot")
        XCTAssertEqual(storeData["transaction_id"] as? String, transactionId)
        XCTAssertEqual(storeData["product_id"] as? String, StoreIds.monthly)

        // In subscription-management mode purchase() finishes strictly after
        // the backend answered 200, so by the time it returns the transaction
        // is already gone from the unfinished set — no polling, an absence that
        // appears late would be indistinguishable from an absence that was
        // never there.
        let unfinished: [Qonversion.Transaction] = await world.storeKitFacade.unfinishedTransactions()
        XCTAssertFalse(unfinished.contains { $0.id == transactionId }, "a reported purchase must be finished with the store")

        // Negative control on the launch mode: Analytics hands the transaction
        // lifecycle to the host app, so a REPORTED purchase must still be left
        // unfinished. This is also the positive proof that
        // unfinishedTransactions() can see anything at all — without it, the
        // absence asserted above could mean "never visible".
        let analyticsDefaults: UserDefaults = TestDefaults.makeIsolated()
        let analyticsWorld = StoreWorld(userDefaults: analyticsDefaults, launchMode: .analytics)
        analyticsWorld.stubBackend()

        let consumable: Qonversion.Product = try await loadProduct(QonversionIds.consumable, in: analyticsWorld)
        let analyticsResult: Qonversion.PurchaseResult = try await analyticsWorld.purchasesManager.purchase(consumable, options: nil)
        let analyticsId: String = try XCTUnwrap(analyticsResult.transaction.id)

        let analyticsNetwork: StubNetworkProvider = analyticsWorld.network
        XCTAssertNotNil(Self.report(for: analyticsId, in: analyticsNetwork.recordedRequests("POST", "/v4/users/*/purchases")), "an Analytics mode purchase is still reported to the backend")

        let analyticsFacade: StoreKitFacade = analyticsWorld.storeKitFacade
        await waitUntilAsync("the Analytics mode purchase is visible as unfinished") {
            let pending: [Qonversion.Transaction] = await analyticsFacade.unfinishedTransactions()
            return pending.contains { $0.id == analyticsId }
        }
        let analyticsUnfinished: [Qonversion.Transaction] = await analyticsFacade.unfinishedTransactions()
        XCTAssertTrue(analyticsUnfinished.contains { $0.id == analyticsId }, "in Analytics mode the host app owns the lifecycle, so the SDK must not finish the purchase")

        // Second control, orthogonal to the mode: even in subscription
        // management a purchase whose report never reached the backend must
        // stay unfinished, so it can be re-reported later.
        let offlineDefaults: UserDefaults = TestDefaults.makeIsolated()
        let offlineWorld = StoreWorld(userDefaults: offlineDefaults)
        offlineWorld.stubBackend()
        let transportError: URLError = URLError(.notConnectedToInternet)
        offlineWorld.network.stub("POST", "/v4/users/*/purchases", transportError: transportError)

        let offlineConsumable: Qonversion.Product = try await loadProduct(QonversionIds.consumable, in: offlineWorld)
        let offlineResult: Qonversion.PurchaseResult = try await offlineWorld.purchasesManager.purchase(offlineConsumable, options: nil)
        let offlineId: String = try XCTUnwrap(offlineResult.transaction.id)

        let stillUnfinished: [Qonversion.Transaction] = await offlineWorld.storeKitFacade.unfinishedTransactions()
        XCTAssertTrue(stillUnfinished.contains { $0.id == offlineId }, "an unreported purchase must stay unfinished")
    }

    // MARK: - c. the signed expiration wins over the local approximation

    func testEntitlementExpirationComesFromTheSignedTransaction() async throws {
        try requireStoreKit()

        world.stubEmptyRemoteEntitlements()
        await world.productsManager.loadProductPermissions()
        let monthly: Qonversion.Product = try await loadProduct(QonversionIds.monthly)

        let result: Qonversion.PurchaseResult = try await world.purchasesManager.purchase(monthly, options: nil)
        let transaction: Qonversion.Transaction = result.transaction

        let signedExpiration: Date = try XCTUnwrap(transaction.expirationDate, "the store signs the expiration of a subscription transaction")
        let purchaseDate: Date = try XCTUnwrap(transaction.purchaseDate)

        // Diagnosability: this scenario only means something while the trial is
        // the offer being purchased. If the configuration ever loses it, fail
        // here with "the trial was not applied" instead of further down with a
        // confusing date mismatch.
        let weekAfterPurchase: Date = purchaseDate.addingTimeInterval(7 * 24 * 60 * 60)
        let trialTolerance: TimeInterval = 5 * 60
        XCTAssertEqual(signedExpiration.timeIntervalSince(weekAfterPurchase), 0, accuracy: trialTolerance, "the one week free trial was not applied to this purchase")

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
        try requireStoreKit()

        // Eligibility is a function of the store account's history: diagnose
        // leaked state from a previous test at its source.
        XCTAssertTrue(session.allTransactions().isEmpty, "the store session must start clean, otherwise eligibility is answered from leaked transactions")

        let before: [String: Qonversion.IntroEligibilityStatus] = try await world.productsManager.checkTrialIntroEligibility(productIds: [QonversionIds.monthly, QonversionIds.yearly, QonversionIds.lifetime])

        XCTAssertEqual(before[QonversionIds.monthly], .eligible, "a fresh store account is eligible for the configured trial")
        XCTAssertEqual(before[QonversionIds.yearly], .nonIntroOrTrialProduct, "the yearly product has no introductory offer")
        XCTAssertEqual(before[QonversionIds.lifetime], .nonIntroOrTrialProduct)

        let monthly: Qonversion.Product = try await loadProduct(QonversionIds.monthly)
        _ = try await world.purchasesManager.purchase(monthly, options: nil)

        // The store updates the eligibility asynchronously after the purchase.
        let manager: ProductsManagerInterface = world.productsManager
        await waitUntilAsync("the consumed trial makes the user ineligible") {
            let statuses: [String: Qonversion.IntroEligibilityStatus] = (try? await manager.checkTrialIntroEligibility(productIds: [QonversionIds.monthly])) ?? [:]
            return statuses[QonversionIds.monthly] == .ineligible
        }

        let after: [String: Qonversion.IntroEligibilityStatus] = try await world.productsManager.checkTrialIntroEligibility(productIds: [QonversionIds.monthly])
        XCTAssertEqual(after[QonversionIds.monthly], .ineligible, "the consumed trial makes the user ineligible")
    }

    // MARK: - e. restore

    func testRestoreReportsThePurchasedTransactionToAFreshSession() async throws {
        try requireStoreKit()

        let monthly: Qonversion.Product = try await loadProduct(QonversionIds.monthly)
        let result: Qonversion.PurchaseResult = try await world.purchasesManager.purchase(monthly, options: nil)
        let purchasedId: String = try XCTUnwrap(result.transaction.id)

        // Restore has to happen in a SECOND SDK session: the purchasing one
        // already claimed the transaction in its reports gate, so restoring
        // there would report nothing and assert nothing. A fresh graph over the
        // same store account is exactly the reinstall case restore exists for.
        let restoreDefaults: UserDefaults = TestDefaults.makeIsolated()
        let restoreWorld = StoreWorld(userDefaults: restoreDefaults)
        restoreWorld.stubBackend()
        // With the backend unreachable for entitlements, anything the restore
        // returns must have been calculated locally from the store.
        let transportError: URLError = URLError(.notConnectedToInternet)
        restoreWorld.network.stub("GET", "/v4/users/*/entitlements", transportError: transportError)
        try await restoreWorld.warmCatalog()

        let entitlements: [String: Qonversion.Entitlement] = try await restoreWorld.purchasesManager.restore()

        // The store side: a real AppStore.sync() plus the mapped transactions.
        let reports: [URLRequest] = restoreWorld.network.recordedRequests("POST", "/v4/users/*/purchases")
        let report: URLRequest = try XCTUnwrap(Self.report(for: purchasedId, in: reports), "restore must report the purchased transaction")
        XCTAssertEqual(report.value(forHTTPHeaderField: "Trigger"), "Restore")
        let body: [String: Any] = try XCTUnwrap(report.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let storeData: [String: Any] = try XCTUnwrap(body["store_data"] as? [String: Any])
        XCTAssertEqual(storeData["product_id"] as? String, StoreIds.monthly)
        let receipt: String = try XCTUnwrap(storeData["receipt"] as? String, "a restored transaction keeps its signed proof")
        let payload: [String: Any] = try XCTUnwrap(Self.jwsPayload(receipt))
        XCTAssertEqual(payload["transactionId"] as? String, purchasedId)

        // The entitlements can only come from the local calculation here.
        let premium: Qonversion.Entitlement = try XCTUnwrap(entitlements[QonversionIds.premium], "the restored transaction must grant its entitlement locally")
        XCTAssertTrue(premium.active)
        XCTAssertEqual(premium.productId, QonversionIds.monthly)
    }

    // MARK: - f. currentEntitlements

    func testCurrentEntitlementsReflectTheActivePurchase() async throws {
        try requireStoreKit()

        world.stubEmptyRemoteEntitlements()
        await world.productsManager.loadProductPermissions()
        let monthly: Qonversion.Product = try await loadProduct(QonversionIds.monthly)
        let result: Qonversion.PurchaseResult = try await world.purchasesManager.purchase(monthly, options: nil)
        let purchasedId: String = try XCTUnwrap(result.transaction.id)

        // The store publishes the entitlement asynchronously after the purchase.
        let facade: StoreKitFacade = world.storeKitFacade
        await waitUntilAsync("the active subscription appears in the store entitlements") {
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
        try requireStoreKit()

        guard #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *) else {
            throw XCTSkip("SKTestSession.buyProduct(identifier:options:) requires iOS 17 / macOS 14 / tvOS 17 / watchOS 10")
        }

        // Warm the catalog so the local calculation has products to work with.
        _ = try await world.productsManager.products()

        // No settling wait before the trigger: Transaction.updates replays
        // unfinished transactions to late subscribers, so a listener that
        // attaches after the purchase still receives it. Attachment timing is
        // therefore not observable here — only the effect is, and that is
        // polled with a deadline below.
        world.purchasesManager.startObservingTransactions()

        let network: StubNetworkProvider = world.network
        let outOfBand: StoreKit.Transaction = try await session.buyProduct(identifier: StoreIds.yearly)
        let outOfBandId: String = String(outOfBand.id)

        await waitUntil("the observed transaction is reported to the backend") {
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
        let payload: [String: Any] = try XCTUnwrap(Self.jwsPayload(receipt), "the observed transaction must carry its signed payload")
        XCTAssertEqual(payload["transactionId"] as? String, outOfBandId)
        XCTAssertEqual(payload["productId"] as? String, StoreIds.yearly)

        // Subscription management finishes an observed transaction after the
        // backend confirms it.
        let facade: StoreKitFacade = world.storeKitFacade
        await waitUntilAsync("the confirmed transaction is finished with the store") {
            let pending: [Qonversion.Transaction] = await facade.unfinishedTransactions()
            return !pending.contains { $0.id == outOfBandId }
        }
        let unfinished: [Qonversion.Transaction] = await facade.unfinishedTransactions()
        XCTAssertFalse(unfinished.contains { $0.id == outOfBandId })
    }
}

// MARK: - Environment probe

private extension StoreKitSessionTests {

    static let requireStoreKitVariable: String = "QONVERSION_REQUIRE_STOREKIT"

    /// Whether this run must exercise real StoreKit — an unusable store then
    /// fails instead of skipping.
    static var storeKitIsRequired: Bool {
        let raw: String? = ProcessInfo.processInfo.environment[requireStoreKitVariable]
        guard let value: String = raw?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return false }

        return value != "0" && value.lowercased() != "false" && value.lowercased() != "no"
    }

    /// The bundled configuration. A host-app test target carries the file in
    /// its own bundle; SwiftPM puts it in the generated resource bundle that
    /// only Bundle.module knows about (and which fatalErrors when absent, so
    /// it is asked last and only where it exists).
    static func configurationURL() -> URL? {
        let testBundle: Bundle = Bundle(for: StoreKitSessionTests.self)
        if let url: URL = testBundle.url(forResource: "Qonversion", withExtension: "storekit") {
            return url
        }

        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "Qonversion", withExtension: "storekit")
        #else
        return nil
        #endif
    }

    /// Separates "the store is not here" from "the configuration is wrong".
    static func probeStoreKitEnvironment() async -> StoreKitProbe {
        guard let url: URL = configurationURL() else {
            return .broken("the Qonversion.storekit resource is missing from the test bundle.")
        }

        let session: SKTestSession
        do {
            session = try SKTestSession(contentsOf: url)
        } catch {
            return .broken("SKTestSession rejected " + url.lastPathComponent + ": " + String(describing: error))
        }

        session.disableDialogs = true
        session.clearTransactions()

        // The store may never answer when the agent refused the configuration;
        // a deadline keeps a hostless run from hanging here.
        let expected: Set<String> = StoreIds.all
        guard let loaded: [StoreKit.Product] = await productsWithDeadline(expected, seconds: 20) else {
            return .unavailable("the store did not answer the product request in time.")
        }
        guard !loaded.isEmpty else {
            return .unavailable("the store returned no products for the bundled configuration.")
        }

        let loadedIds: Set<String> = Set(loaded.map { $0.id })
        guard loadedIds == expected else {
            let missing: [String] = expected.subtracting(loadedIds).sorted()
            let unexpected: [String] = loadedIds.subtracting(expected).sorted()
            var details: [String] = []
            if !missing.isEmpty {
                details.append("the store does not know " + missing.joined(separator: ", "))
            }
            if !unexpected.isEmpty {
                details.append("it answered with unrequested " + unexpected.joined(separator: ", "))
            }
            return .broken("the product set does not match the configuration — " + details.joined(separator: "; ") + ". Check the productID values in Qonversion.storekit.")
        }

        return .ready(session)
    }

    /// The loaded products, or nil when the store neither answered nor failed
    /// within the deadline.
    static func productsWithDeadline(_ ids: Set<String>, seconds: TimeInterval) async -> [StoreKit.Product]? {
        return await withTaskGroup(of: [StoreKit.Product]?.self) { group in
            group.addTask {
                return try? await StoreKit.Product.products(for: ids)
            }
            group.addTask {
                let nanoseconds: UInt64 = UInt64(seconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                return nil
            }

            let first: [StoreKit.Product]?? = await group.next()
            group.cancelAll()

            return first ?? nil
        }
    }
}

// MARK: - Helpers

private extension StoreKitSessionTests {

    func loadProduct(_ qonversionId: String) async throws -> Qonversion.Product {
        return try await loadProduct(qonversionId, in: world)
    }

    func loadProduct(_ qonversionId: String, in storeWorld: StoreWorld) async throws -> Qonversion.Product {
        let products: [Qonversion.Product] = try await storeWorld.productsManager.products()

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

    /// The decoded payload segment of a signed transaction — the identity of
    /// the purchase, not just its shape.
    static func jwsPayload(_ jws: String) -> [String: Any]? {
        let segments: [Substring] = jws.split(separator: ".")
        guard segments.count == 3 else { return nil }

        var encoded: String = String(segments[1])
        encoded = encoded.replacingOccurrences(of: "-", with: "+")
        encoded = encoded.replacingOccurrences(of: "_", with: "/")
        let remainder: Int = encoded.count % 4
        if remainder > 0 {
            encoded += String(repeating: "=", count: 4 - remainder)
        }

        guard let data: Data = Data(base64Encoded: encoded) else { return nil }
        let decoded: Any? = try? JSONSerialization.jsonObject(with: data)

        return decoded as? [String: Any]
    }

    /// Polls until the condition holds; a timeout is reported as a failure at
    /// the call site, so it can never read as an instant success.
    @discardableResult
    func waitUntil(_ description: String, timeout: TimeInterval = 5.0, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("timed out after \(timeout)s waiting until " + description, file: file, line: line)
        return false
    }

    @discardableResult
    func waitUntilAsync(_ description: String, timeout: TimeInterval = 5.0, file: StaticString = #filePath, line: UInt = #line, _ condition: () async -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("timed out after \(timeout)s waiting until " + description, file: file, line: line)
        return false
    }
}

#endif
