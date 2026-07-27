//
//  ProductsManagerTests.swift
//  QonversionUnitTests
//
//  Fixation tests for ProductsManager: lock in the current behavior as-is.
//

import XCTest
import StoreKit
@testable import Qonversion

final class ProductsManagerTests: XCTestCase {

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
        manager = makeManager()
    }

    private func makeManager() -> ProductsManager {
        ProductsManager(
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
        productsService = nil
        storeKitFacade = nil
        localStorage = nil
        super.tearDown()
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Helpers

    private func makeProduct(qonversionId: String = "q_main", storeId: String = "store_main") -> Qonversion.Product {
        return Qonversion.Product(qonversionId: qonversionId, storeId: storeId, offeringId: nil)
    }

    func testConcurrentProductsCallsShareOneRound() async throws {
        productsService.productsResult = [makeProduct()]
        let gate = ProductsAsyncGate()
        productsService.onProducts = { await gate.wait() }

        async let first = manager.products()
        await waitUntil { self.productsService.productsCallsCount >= 1 }
        async let second = manager.products()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await gate.open()
        _ = try await first
        _ = try await second

        XCTAssertEqual(productsService.productsCallsCount, 1, "N concurrent callers must not issue N API rounds")
    }

    // MARK: - offline catalog for the local entitlements calculation (A2.5)

    func testCachedProductsFallBackToThePersistedCatalog() async throws {
        productsService.productsResult = [makeProduct(qonversionId: "q_pro", storeId: "store_pro")]
        _ = try await manager.products()

        // A fresh launch: the in-memory cache is empty, the persisted catalog answers.
        let coldManager = makeManager()
        let products = coldManager.cachedProducts()

        XCTAssertEqual(products.map(\.qonversionId), ["q_pro"], "the offline entitlements calculation must not starve on a cold start")
    }

    func testCachedProductsFallBackToTheBundledFileWhenNothingWasPersisted() {
        fallbackService.fallbackData = FallbackData(products: [makeProduct(qonversionId: "q_fb", storeId: "store_fb")], productsPermissions: nil)

        let products = manager.cachedProducts()

        XCTAssertEqual(products.map(\.qonversionId), ["q_fb"])
    }

    // MARK: - Fallback file accessibility

    func testFallbackFileAccessibleWhenBundledDataParses() {
        fallbackService.fallbackData = FallbackData(products: nil, productsPermissions: ["pro": ["premium"]])

        XCTAssertTrue(manager.isFallbackFileAccessible())
    }

    func testFallbackFileNotAccessibleWithoutBundledData() {
        fallbackService.fallbackData = nil

        XCTAssertFalse(manager.isFallbackFileAccessible())
    }

    // MARK: - In-memory cache

    func testProductsReturnsInMemoryCacheWithoutServiceCall() async throws {
        manager.loadedProducts = [makeProduct()]

        let result = try await manager.products()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.qonversionId, "q_main")
        XCTAssertEqual(productsService.productsCallsCount, 0)
        XCTAssertTrue(storeKitFacade.requestedProductIds.isEmpty)
    }

    // MARK: - Store products request

    func testProductsRequestsStoreProductsForAllStoreIds() async throws {
        productsService.productsResult = [
            makeProduct(qonversionId: "q_a", storeId: "store_a"),
            makeProduct(qonversionId: "q_b", storeId: "store_b"),
        ]

        _ = try await manager.products()

        XCTAssertEqual(storeKitFacade.requestedProductIds, [["store_a", "store_b"]])
    }

    // MARK: - Enrichment

    // The catalog is backend-driven: a product the store does not know (e.g.
    // a Stripe-only product) stays in the result unenriched instead of
    // disappearing from the paywall.
    func testProductsWithoutStoreMatchesAreKeptUnenriched() async throws {
        productsService.productsResult = [makeProduct()]
        storeKitFacade.productsResult = [StoreProductWrapper(product: nil)]

        let result = try await manager.products()

        XCTAssertEqual(result.map(\.qonversionId), ["q_main"])
        XCTAssertFalse(result[0].isStoreProductLinked)
        XCTAssertEqual(productsService.productsCallsCount, 1)
        // "not linked" alone would also hold if the join had never run. The
        // store WAS asked, and — the enrichment-retry seam — the result was
        // cached, which only a join that SUCCEEDED does: a failed one is left
        // uncached so the next call retries it.
        XCTAssertEqual(storeKitFacade.requestedProductIds, [["store_main"]])
        _ = try await manager.products()
        XCTAssertEqual(productsService.productsCallsCount, 1, "a successful join caches its result")
        XCTAssertEqual(storeKitFacade.requestedProductIds.count, 1)
    }

    func testUnenrichedProductsAreCachedLikeAnyOtherResult() async throws {
        productsService.productsResult = [makeProduct()]
        storeKitFacade.productsResult = []

        _ = try await manager.products()
        _ = try await manager.products()

        XCTAssertEqual(productsService.productsCallsCount, 1, "the backend answer is authoritative — no refetch loop")
    }

    // MARK: - StoreKit error fallback

    // Fixates current behavior: StoreKit loading errors are swallowed (only logged) and
    // the manager falls back to the unenriched API products.
    func testStoreKitErrorFallsBackToUnenrichedProducts() async throws {
        productsService.productsResult = [
            makeProduct(qonversionId: "q_a", storeId: "store_a"),
            makeProduct(qonversionId: "q_b", storeId: "store_b"),
        ]
        storeKitFacade.productsError = MockError.stubbed

        let result = try await manager.products()

        XCTAssertEqual(result.map { $0.qonversionId }, ["q_a", "q_b"])
        XCTAssertEqual(result.map { $0.isStoreProductLinked }, [false, false])
    }

    // A StoreKit outage is transient. Caching the unenriched products made it
    // permanent for the whole session: prices and offers never came back
    // however long the store stayed healthy afterwards.
    func testAFailedEnrichmentIsNotCachedSoTheNextCallRetriesIt() async throws {
        productsService.productsResult = [makeProduct()]
        storeKitFacade.productsError = MockError.stubbed

        let first = try await manager.products()
        XCTAssertEqual(first.map(\.qonversionId), ["q_main"], "the caller still gets the catalog")
        XCTAssertTrue(manager.loadedProducts.isEmpty, "an unenriched result must not become the cache")

        storeKitFacade.productsError = nil
        storeKitFacade.productsResult = [StoreProductWrapper(product: nil)]
        _ = try await manager.products()

        XCTAssertEqual(storeKitFacade.requestedProductIds.count, 2, "the enrichment must be retried")
    }

    func testAProductWithoutAStoreIdIsReportedInTheLog() async throws {
        // Never silently: an empty storeId means the row carried neither
        // store_id nor apple_product_id, which is almost always a mistake in
        // the fallback file rather than a Stripe-only product.
        let messages = LogCollector()
        let manager = ProductsManager(
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: localStorage,
            fallbackService: fallbackService,
            logger: LoggerWrapper(sink: { _, message in messages.append(message) })
        )
        productsService.productsResult = [makeProduct(qonversionId: "q_ok"), makeProduct(qonversionId: "q_no_store", storeId: "")]

        _ = try await manager.products()

        XCTAssertTrue(messages.all().contains { $0.contains("q_no_store") },
                      "the developer must be told which product has no App Store id")
        XCTAssertFalse(messages.all().contains { $0.contains("q_ok") })
    }

    func testAFallbackProductWithoutAStoreIdIsReportedInTheLog() async throws {
        // The fallback file is exactly where a row with neither `store_id` nor
        // `apple_product_id` comes from, and that path returns early — the
        // reporting used to sit below the return and never ran for it.
        let messages = LogCollector()
        let manager = ProductsManager(
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: localStorage,
            fallbackService: fallbackService,
            logger: LoggerWrapper(sink: { _, message in messages.append(message) })
        )
        productsService.error = QonversionError(type: .productsLoadingFailed)
        let fallbackProducts: [Qonversion.Product] = [makeProduct(qonversionId: "q_fallback_no_store", storeId: "")]
        fallbackService.fallbackData = FallbackData(products: fallbackProducts, productsPermissions: nil)

        _ = try await manager.products()

        XCTAssertTrue(messages.all().contains { $0.contains("q_fallback_no_store") },
                      "a fallback row with no App Store product id must not be admitted silently")
    }

    func testAStoreIdTheStoreDoesNotKnowIsReportedInTheLog() async throws {
        // A paywall with no price is the symptom; the id missing from App
        // Store Connect is the cause, and only the SDK can see it.
        let messages = LogCollector()
        let manager = ProductsManager(
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: localStorage,
            fallbackService: fallbackService,
            logger: LoggerWrapper(sink: { _, message in messages.append(message) })
        )
        productsService.productsResult = [makeProduct(qonversionId: "q_main", storeId: "com.app.unknown")]
        storeKitFacade.productsResult = []

        _ = try await manager.products()

        XCTAssertTrue(messages.all().contains { $0.contains("com.app.unknown") },
                      "an id the store returned nothing for must be named")
    }

    func testAProductWithNoStoreIdIsNotReportedAsMissingFromTheStore() async throws {
        // A Stripe-only product is never asked about, so it must not show up
        // in the "the store returned nothing" list.
        let messages = LogCollector()
        let manager = ProductsManager(
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: localStorage,
            fallbackService: fallbackService,
            logger: LoggerWrapper(sink: { _, message in messages.append(message) })
        )
        productsService.productsResult = [makeProduct(qonversionId: "q_stripe", storeId: "")]
        storeKitFacade.productsResult = []

        _ = try await manager.products()

        XCTAssertFalse(messages.all().contains { $0.contains("returned no product for these ids") })
    }

    func testARequestedProductIdAbsentFromTheCatalogIsReportedInTheLog() async throws {
        let messages = LogCollector()
        let manager = ProductsManager(
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: localStorage,
            fallbackService: fallbackService,
            logger: LoggerWrapper(sink: { _, message in messages.append(message) })
        )
        productsService.productsResult = [makeProduct(qonversionId: "q_main")]

        _ = try await manager.checkTrialIntroEligibility(productIds: ["q_main", "q_typo"])

        XCTAssertTrue(messages.all().contains { $0.contains("q_typo") },
                      ".unknown alone hides a typo in the product id")
    }

    // MARK: - Service error

    // Without a bundled fallback file, a products service error propagates to
    // the caller as-is and the injected local storage is never consulted.
    func testServiceErrorPropagatesWithoutDiskFallback() async {
        // The REAL key: seeding "products" proved nothing, the manager never
        // looks there.
        try? localStorage.set([makeProduct(qonversionId: "q_persisted")], forKey: "qonversion.keys.products")
        productsService.error = QonversionError(type: .productsLoadingFailed)

        do {
            _ = try await manager.products()
            XCTFail("Expected products() to rethrow the service error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .productsLoadingFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(storeKitFacade.requestedProductIds.isEmpty)
        XCTAssertTrue(manager.loadedProducts.isEmpty)
    }

    // MARK: - bundled fallback file

    func testServiceErrorFallsBackToBundledProducts() async throws {
        productsService.error = QonversionError(type: .productsLoadingFailed)
        fallbackService.fallbackData = FallbackData(
            products: [makeProduct(qonversionId: "q_fallback", storeId: "store_fallback")],
            productsPermissions: nil
        )
        storeKitFacade.productsError = MockError.stubbed

        let result = try await manager.products()

        XCTAssertEqual(result.map { $0.qonversionId }, ["q_fallback"])
        // The bundled snapshot must not shadow the API: the next call retries.
        XCTAssertTrue(manager.loadedProducts.isEmpty)
        _ = try? await manager.products()
        XCTAssertEqual(productsService.productsCallsCount, 2)
    }

    func testCachedProductPermissionsFallsBackToBundledMapping() {
        fallbackService.fallbackData = FallbackData(products: nil, productsPermissions: ["pro": ["premium"]])

        XCTAssertEqual(manager.cachedProductPermissions(), ["pro": ["premium"]])
    }

    func testPersistedMappingIsPreferredOverBundledFallback() async {
        productsService.productPermissionsResult = ["pro": ["from_api"]]
        await manager.loadProductPermissions()
        fallbackService.fallbackData = FallbackData(products: nil, productsPermissions: ["pro": ["from_file"]])

        XCTAssertEqual(manager.cachedProductPermissions(), ["pro": ["from_api"]])
    }

    // MARK: - product permissions mapping cache

    // The mapping powers local entitlements calculation when the backend is
    // unreachable: every successful fetch refreshes the persistent cache; a
    // failed fetch leaves the previously cached mapping intact.

    func testLoadProductPermissionsCachesMappingOnSuccess() async {
        productsService.productPermissionsResult = ["pro": ["premium"]]

        await manager.loadProductPermissions()

        XCTAssertEqual(manager.cachedProductPermissions(), ["pro": ["premium"]])
    }

    func testEverySuccessfulLoadRefreshesTheCache() async {
        productsService.productPermissionsResult = ["pro": ["premium"]]
        await manager.loadProductPermissions()

        productsService.productPermissionsResult = ["pro": ["premium", "extra"], "lite": ["basic"]]
        await manager.loadProductPermissions()

        XCTAssertEqual(manager.cachedProductPermissions(), ["pro": ["premium", "extra"], "lite": ["basic"]])
    }

    func testFailedLoadKeepsPreviouslyCachedMapping() async {
        productsService.productPermissionsResult = ["pro": ["premium"]]
        await manager.loadProductPermissions()

        productsService.productPermissionsError = MockError.stubbed
        await manager.loadProductPermissions()

        XCTAssertEqual(manager.cachedProductPermissions(), ["pro": ["premium"]])
    }

    func testCachedMappingSurvivesManagerRecreation() async {
        productsService.productPermissionsResult = ["pro": ["premium"]]
        await manager.loadProductPermissions()

        // A fresh manager over the same storage reads the persisted cache
        // without hitting the service.
        let recreated = makeManager()

        XCTAssertEqual(recreated.cachedProductPermissions(), ["pro": ["premium"]])
        XCTAssertEqual(productsService.productPermissionsCallsCount, 1)
    }

    func testCachedMappingIsNilWhenNeverLoaded() {
        XCTAssertNil(manager.cachedProductPermissions())
    }

    // MARK: - User change

    func testUserDidChangeClearsLoadedProductsCache() async throws {
        manager.loadedProducts = [makeProduct()]

        manager.userDidChange()

        XCTAssertTrue(manager.loadedProducts.isEmpty)
        // The next demand goes back to the service.
        productsService.productsResult = [makeProduct(qonversionId: "q_new", storeId: "store_new")]
        storeKitFacade.productsError = MockError.stubbed
        let result = try await manager.products()
        XCTAssertEqual(result.map { $0.qonversionId }, ["q_new"])
        XCTAssertEqual(productsService.productsCallsCount, 1)
    }

    func testProductsLoadedForThePreviousUserDoNotSurviveASwitch() async throws {
        // The response belongs to the previous user (products may be
        // personalized) — neither the in-memory cache nor the persisted
        // catalog may end up holding it under the new uid.
        productsService.productsResult = [makeProduct()]
        let gate = ProductsAsyncGate()
        productsService.onProducts = { await gate.wait() }

        async let staleLoad: [Qonversion.Product] = manager.products()
        await waitUntil { self.productsService.productsCallsCount >= 1 }
        manager.userDidChange()
        await gate.open()
        _ = try? await staleLoad

        XCTAssertTrue(manager.loadedProducts.isEmpty, "the previous user's products must not stay cached")
        XCTAssertNil(localStorage.data(forKey: "qonversion.keys.products"), "the previous user's catalog must not be persisted for the new one")
    }

    func testUserDidChangeInvalidatesTheInFlightProductsTask() async throws {
        productsService.productsResult = [makeProduct()]
        let gate = ProductsAsyncGate()
        productsService.onProducts = { await gate.wait() }

        async let staleLoad: [Qonversion.Product] = manager.products()
        await waitUntil { self.productsService.productsCallsCount >= 1 }
        manager.userDidChange()
        await gate.open()
        _ = try? await staleLoad

        productsService.onProducts = nil
        _ = try await manager.products()

        XCTAssertEqual(productsService.productsCallsCount, 2, "the new user must not join the previous user's in-flight load")
    }

    func testACallerArrivingAfterTheSwitchGetsFreshProductsNotTheInFlightOnes() async throws {
        // The load in flight belongs to the previous user; a caller that
        // arrives after the switch must not be served its result.
        productsService.productsResult = [makeProduct(qonversionId: "old", storeId: "store_old")]
        let gate = ProductsAsyncGate()
        productsService.onProducts = { await gate.wait() }

        async let staleLoad: [Qonversion.Product] = manager.products()
        await waitUntil { self.productsService.productsCallsCount >= 1 }
        manager.userDidChange()

        productsService.onProducts = nil
        productsService.productsResult = [makeProduct(qonversionId: "new", storeId: "store_new")]
        let fresh: [Qonversion.Product] = try await manager.products()
        await gate.open()
        _ = try? await staleLoad

        XCTAssertEqual(fresh.map(\.qonversionId), ["new"])
        XCTAssertEqual(manager.loadedProducts.map(\.qonversionId), ["new"], "the previous user's response must not overwrite the new user's catalog")
    }

    // The product → permissions mapping is project-scoped, not user-scoped:
    // it stays valid across a user switch and keeps powering the local
    // entitlements fallback.
    func testUserDidChangeKeepsProductPermissionsMapping() async {
        productsService.productPermissionsResult = ["pro": ["premium"]]
        await manager.loadProductPermissions()

        manager.userDidChange()

        XCTAssertEqual(manager.cachedProductPermissions(), ["pro": ["premium"]])
    }
}

/// A reusable async gate: wait() suspends until open() is called.
private actor ProductsGateStorage {
    var isOpen = false
    var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private final class ProductsAsyncGate: @unchecked Sendable {
    private let storage = ProductsGateStorage()
    func open() async { await storage.open() }
    func wait() async { await storage.wait() }
}

/// Resumes every waiter only once the expected number of them has arrived.
private actor EligibilityBarrier {

    private let expected: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(expected: Int) {
        self.expected = expected
    }

    func arriveAndWait() async {
        if waiters.count + 1 >= expected {
            waiters.forEach { $0.resume() }
            waiters.removeAll()
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

// MARK: - storefront changes and eligibility fan-out

final class ProductsStorefrontTests: XCTestCase {

    private var productsService: MockProductsService!
    private var storeKitFacade: MockStoreKitFacade!
    private var manager: ProductsManager!

    override func setUp() {
        super.setUp()
        productsService = MockProductsService()
        storeKitFacade = MockStoreKitFacade()
        manager = ProductsManager(
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: MockLocalStorage(),
            fallbackService: MockFallbackService(),
            logger: LoggerWrapper()
        )
    }

    override func tearDown() {
        manager = nil
        storeKitFacade = nil
        productsService = nil
        super.tearDown()
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testStorefrontChangeDropsTheEnrichedCatalog() async throws {
        productsService.productsResult = [Qonversion.Product(qonversionId: "q", storeId: "s", offeringId: nil)]
        _ = try await manager.products()
        XCTAssertFalse(manager.loadedProducts.isEmpty)

        manager.startObservingStorefrontChanges()
        await waitUntil { self.storeKitFacade.hasStorefrontSubscriber }
        storeKitFacade.emitStorefrontChange()

        await waitUntil { self.manager.loadedProducts.isEmpty }
        XCTAssertTrue(manager.loadedProducts.isEmpty, "prices and offers must be refetched for the new storefront")
    }

    func testAnInFlightLoadCannotWriteOldStorefrontPricesBack() async throws {
        // The load started before the storefront changed: its prices and
        // offers belong to the old storefront and must never land in the cache
        // the change just dropped.
        let gate = ProductsAsyncGate()
        productsService.productsResult = [Qonversion.Product(qonversionId: "q", storeId: "s", offeringId: nil)]
        productsService.onProducts = { await gate.wait() }
        manager.startObservingStorefrontChanges()
        await waitUntil { self.storeKitFacade.hasStorefrontSubscriber }

        let loading = Task { try await self.manager.products() }
        await waitUntil { self.productsService.productsCallsCount == 1 }
        storeKitFacade.emitStorefrontChange()
        try? await Task.sleep(nanoseconds: 100_000_000)
        await gate.open()
        _ = try? await loading.value

        XCTAssertTrue(manager.loadedProducts.isEmpty, "the pre-change catalog must not be cached for the new storefront")
    }

    func testALoadStartedAfterTheChangeIsNotJoinedToThePreChangeOne() async throws {
        let gate = ProductsAsyncGate()
        productsService.productsResult = [Qonversion.Product(qonversionId: "q", storeId: "s", offeringId: nil)]
        productsService.onProducts = { await gate.wait() }
        manager.startObservingStorefrontChanges()
        await waitUntil { self.storeKitFacade.hasStorefrontSubscriber }

        let loading = Task { try await self.manager.products() }
        await waitUntil { self.productsService.productsCallsCount == 1 }
        storeKitFacade.emitStorefrontChange()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let afterChange = Task { try await self.manager.products() }
        await gate.open()
        _ = try? await loading.value
        _ = try? await afterChange.value

        XCTAssertEqual(productsService.productsCallsCount, 2,
                       "a caller arriving after the change must not be served the pre-change load")
    }

    func testEligibilityChecksRunConcurrentlyAndMapEveryProduct() async {
        // Every product is still asked about — just not one after another.
        let barrier = EligibilityBarrier(expected: 3)
        let answers: [String: Bool?] = ["s0": true, "s1": false, "s2": nil]

        let result: [String: Qonversion.IntroEligibilityStatus] = await ProductsManager.introEligibilities(
            for: ["q0": "s0", "q1": "s1", "q2": "s2"]
        ) { storeId in
            // Resumes only once all three checks are in flight: a sequential
            // implementation would deadlock here.
            await barrier.arriveAndWait()
            return answers[storeId] ?? nil
        }

        XCTAssertEqual(result["q0"], .eligible)
        XCTAssertEqual(result["q1"], .ineligible)
        XCTAssertEqual(result["q2"], .unknown)
    }
}


/// Collects every message the SDK logs.
// @unchecked: the array is lock-guarded.
final class LogCollector: @unchecked Sendable {

    private let lock = NSLock()
    private var messages: [String] = []

    func append(_ message: String) {
        lock.lock()
        messages.append(message)
        lock.unlock()
    }

    func all() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}
