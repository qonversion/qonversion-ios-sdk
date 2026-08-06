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

    private let apiKey: String = "test_api_key"

    /// The key the manager persists the catalog under — scoped by apiKey.
    private var productsKey: String { "qonversion.keys.products." + apiKey }

    override func setUp() {
        super.setUp()
        productsService = MockProductsService()
        storeKitFacade = MockStoreKitFacade()
        localStorage = MockLocalStorage()
        fallbackService = MockFallbackService()
        manager = makeManager()
    }

    private func makeManager(apiKey: String? = nil, catalogCacheLifetime: TimeInterval = ProductsManager.defaultCatalogCacheLifetime) -> ProductsManager {
        ProductsManager(
            apiKey: apiKey ?? self.apiKey,
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: localStorage,
            fallbackService: fallbackService,
            logger: LoggerWrapper(),
            catalogCacheLifetime: catalogCacheLifetime
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
        return Qonversion.Product(qonversionId: qonversionId, storeId: storeId)
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

    // Every path that serves a catalog names its unpriceable rows — the
    // bundled branch below always did, and reporting one but not the other
    // made the warning depend on which call happened to run first.
    func testCachedProductsReportProductsWithoutAStoreIdFromThePersistedCatalog() throws {
        let messages = LogCollector()
        let manager = ProductsManager(
            apiKey: apiKey,
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: localStorage,
            fallbackService: fallbackService,
            logger: LoggerWrapper(sink: { _, message in messages.append(message) })
        )
        let persisted: [Qonversion.Product] = [makeProduct(qonversionId: "q_persisted_no_store", storeId: "")]
        try localStorage.set(persisted, forKey: productsKey)

        let products: [Qonversion.Product] = manager.cachedProducts()

        XCTAssertEqual(products.map(\.qonversionId), ["q_persisted_no_store"])
        XCTAssertTrue(messages.all().contains { $0.contains("q_persisted_no_store") })
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

    // A catalog loaded moments ago is served as it is: a paywall opened three
    // times in a row costs one request, not three.
    func testProductsReturnsFreshInMemoryCacheWithoutServiceCall() async throws {
        productsService.productsResult = [makeProduct()]

        _ = try await manager.products()
        let result = try await manager.products()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.qonversionId, "q_main")
        XCTAssertEqual(productsService.productsCallsCount, 1, "the second call must be served from memory")
    }

    // ...but it does not outlive its lifetime. Without this the in-memory
    // catalog survived for as long as the process did, so a product added in
    // the dashboard never reached an install that had already loaded once.
    func testProductsRefreshesAnExpiredInMemoryCache() async throws {
        let manager = makeManager(catalogCacheLifetime: 0)
        productsService.productsResult = [makeProduct()]

        _ = try await manager.products()
        _ = try await manager.products()

        XCTAssertEqual(productsService.productsCallsCount, 2, "an expired catalog must be reloaded")
    }

    // A refresh that fails must not take the catalog away with it: the caller
    // gets the last one that loaded, which is what it received before the
    // expiry existed.
    func testProductsServesTheStaleCatalogWhenTheRefreshFails() async throws {
        let manager = makeManager(catalogCacheLifetime: 0)
        productsService.productsResult = [makeProduct()]
        _ = try await manager.products()

        productsService.error = QonversionError(type: .invalidResponse, message: nil, error: nil)
        let result = try await manager.products()

        XCTAssertEqual(result.count, 1, "the previously loaded catalog must still be served")
        XCTAssertEqual(result.first?.qonversionId, "q_main")
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
            apiKey: apiKey,
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
            apiKey: apiKey,
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
            apiKey: apiKey,
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
            apiKey: apiKey,
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
            apiKey: apiKey,
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

    // The last rung of the ladder: an EMPTY persisted catalog and an EMPTY
    // bundled product list are not answers, so the service error still reaches
    // the caller instead of an empty paywall being presented as a success.
    func testServiceErrorPropagatesWhenNeitherSnapshotHasProducts() async throws {
        try localStorage.set([Qonversion.Product](), forKey: productsKey)
        fallbackService.fallbackData = FallbackData(products: [], productsPermissions: ["pro": ["premium"]])
        productsService.error = QonversionError(type: .productsLoadingFailed)

        do {
            let result: [Qonversion.Product] = try await manager.products()
            XCTFail("Expected products() to rethrow the service error, got \(result.map(\.qonversionId))")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .productsLoadingFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(storeKitFacade.requestedProductIds.isEmpty, "an empty snapshot must not even be taken to the store")
        XCTAssertTrue(manager.loadedProducts.isEmpty)
    }

    // The same with nothing stored at all: no persisted blob, no bundled file.
    func testServiceErrorPropagatesWithNothingToFallBackOn() async {
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

    // MARK: - persisted catalog fallback (A2-1)

    // An offline cold start must not empty the paywall of every app that does
    // not ship a fallback file: the catalog of the last successful load is
    // served instead, exactly as the legacy SDK did.
    func testServiceErrorFallsBackToThePersistedCatalog() async throws {
        let persisted: [Qonversion.Product] = [makeProduct(qonversionId: "q_persisted", storeId: "store_persisted")]
        try localStorage.set(persisted, forKey: productsKey)
        productsService.error = QonversionError(type: .productsLoadingFailed)

        let result: [Qonversion.Product] = try await manager.products()

        XCTAssertEqual(result.map(\.qonversionId), ["q_persisted"])
        // The store WAS asked about them: an unenriched paywall has no prices.
        XCTAssertEqual(storeKitFacade.requestedProductIds, [["store_persisted"]])
    }

    // The persisted catalog is what the backend last actually said for THIS
    // user; the bundled file is a build-time snapshot of the whole project.
    func testThePersistedCatalogWinsOverTheBundledFile() async throws {
        let persisted: [Qonversion.Product] = [makeProduct(qonversionId: "q_persisted", storeId: "store_persisted")]
        try localStorage.set(persisted, forKey: productsKey)
        let bundled: [Qonversion.Product] = [makeProduct(qonversionId: "q_fallback", storeId: "store_fallback")]
        fallbackService.fallbackData = FallbackData(products: bundled, productsPermissions: nil)
        productsService.error = QonversionError(type: .productsLoadingFailed)

        let result: [Qonversion.Product] = try await manager.products()

        XCTAssertEqual(result.map(\.qonversionId), ["q_persisted"])
    }

    // Like the bundled file, the persisted catalog answers one call only — it
    // must not shadow the API, and a store outage during it must not be cached.
    func testThePersistedCatalogAnswerIsNotCached() async throws {
        let persisted: [Qonversion.Product] = [makeProduct(qonversionId: "q_persisted", storeId: "store_persisted")]
        try localStorage.set(persisted, forKey: productsKey)
        productsService.error = QonversionError(type: .productsLoadingFailed)
        storeKitFacade.productsError = MockError.stubbed

        let result: [Qonversion.Product] = try await manager.products()

        XCTAssertEqual(result.map(\.qonversionId), ["q_persisted"], "a store outage must not swallow the catalog")
        XCTAssertTrue(manager.loadedProducts.isEmpty)
        _ = try? await manager.products()
        XCTAssertEqual(productsService.productsCallsCount, 2, "the next call must retry the API")
    }

    // The write itself predates this branch. What is new is that the blob is
    // now served to callers, so the overwrite has to be followed through to
    // the fallback: the catalog a later failing load serves must be the fresh
    // one, never the catalog it replaced.
    func testASuccessfulLoadOverwritesThePersistedCatalogAndTheFallbackServesTheFreshOne() async throws {
        let stale: [Qonversion.Product] = [makeProduct(qonversionId: "q_stale", storeId: "store_stale")]
        try localStorage.set(stale, forKey: productsKey)
        productsService.productsResult = [makeProduct(qonversionId: "q_fresh", storeId: "store_fresh")]

        _ = try await manager.products()

        let stored: [Qonversion.Product]? = try localStorage.object(forKey: productsKey, dataType: [Qonversion.Product].self)
        XCTAssertEqual(stored?.map(\.qonversionId), ["q_fresh"])

        // A later launch over the same storage, offline this time.
        let coldManager: ProductsManager = makeManager()
        productsService.error = QonversionError(type: .productsLoadingFailed)
        let served: [Qonversion.Product] = try await coldManager.products()

        XCTAssertEqual(served.map(\.qonversionId), ["q_fresh"])
    }

    // Everything that goes through products() inherits the fallback: an
    // eligibility check offline must answer from the same catalog.
    //
    // .unknown alone proves nothing — it is also what a product MISSING from
    // the catalog gets. The two paths are told apart by their side effects:
    // the served product is taken to the store and is never named as absent
    // from the catalog.
    func testTrialIntroEligibilityIsAnsweredFromThePersistedCatalog() async throws {
        let messages = LogCollector()
        let manager = ProductsManager(
            apiKey: apiKey,
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: localStorage,
            fallbackService: fallbackService,
            logger: LoggerWrapper(sink: { _, message in messages.append(message) })
        )
        let persisted: [Qonversion.Product] = [makeProduct(qonversionId: "q_persisted", storeId: "store_persisted")]
        try localStorage.set(persisted, forKey: productsKey)
        productsService.error = QonversionError(type: .productsLoadingFailed)

        let result: [String: Qonversion.IntroEligibilityStatus] = try await manager.checkTrialIntroEligibility(productIds: ["q_persisted", "q_absent"])

        XCTAssertEqual(result["q_persisted"], .unknown, "an unlinked product is unknown, not a missing-catalog error")
        XCTAssertEqual(storeKitFacade.requestedProductIds, [["store_persisted"]],
                       "the persisted catalog answered: its product went to the store for enrichment")
        XCTAssertFalse(messages.all().contains { $0.contains("\"q_persisted\"") },
                       "a product served from the persisted catalog must not be reported as absent from it")
        // The control: a product that really is absent takes the other path.
        XCTAssertEqual(result["q_absent"], .unknown)
        XCTAssertTrue(messages.all().contains { $0.contains("\"q_absent\"") })
    }

    // MARK: - persisted catalog and the project key

    // products() serves the persisted blob publicly now, so it must be scoped
    // to the project it came from: an app that switches project keys and whose
    // first load under the new one fails would otherwise show the OTHER
    // project's catalog on its paywall.
    func testACatalogPersistedUnderAnotherProjectKeyIsNotServed() async throws {
        let firstProjectManager: ProductsManager = makeManager(apiKey: "project_key_1")
        productsService.productsResult = [makeProduct(qonversionId: "q_project_one", storeId: "store_project_one")]
        _ = try await firstProjectManager.products()

        let secondProjectManager: ProductsManager = makeManager(apiKey: "project_key_2")
        productsService.error = QonversionError(type: .productsLoadingFailed)

        do {
            let result: [Qonversion.Product] = try await secondProjectManager.products()
            XCTFail("another project's catalog must never reach a paywall, got \(result.map(\.qonversionId))")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .productsLoadingFailed)
        }

        XCTAssertTrue(secondProjectManager.cachedProducts().isEmpty,
                      "the local entitlements calculation must not read another project's catalog either")
    }

    // MARK: - persisted catalog and the user generation

    // The generation snapshot taken before the request covers the persisted
    // read too. A user switch landing while the request is in flight makes
    // the catch resume under another user, and the catalog behind the key by
    // then is that other user's — it must not be served.
    func testAUserSwitchDuringTheRequestBlocksThePersistedFallback() async throws {
        productsService.error = QonversionError(type: .productsLoadingFailed)
        let gate = ProductsAsyncGate()
        productsService.onProducts = { await gate.wait() }

        async let staleLoad: [Qonversion.Product] = manager.products()
        await waitUntil { self.productsService.productsCallsCount >= 1 }
        manager.userDidChange()
        // The new user's own load persists ITS catalog under the same key
        // while the previous user's request is still in flight.
        let otherUsersCatalog: [Qonversion.Product] = [makeProduct(qonversionId: "q_other_user", storeId: "store_other_user")]
        try localStorage.set(otherUsersCatalog, forKey: productsKey)
        await gate.open()

        do {
            let result: [Qonversion.Product] = try await staleLoad
            XCTFail("a load that started under the previous user must not be answered from another user's catalog, got \(result.map(\.qonversionId))")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .productsLoadingFailed)
        }
    }

    // The bundled file is a build-time snapshot of the whole project, not of
    // one user: skipping the persisted catalog after a switch still leaves it
    // serveable.
    func testAUserSwitchDuringTheRequestStillFallsThroughToTheBundledFile() async throws {
        productsService.error = QonversionError(type: .productsLoadingFailed)
        fallbackService.fallbackData = FallbackData(
            products: [makeProduct(qonversionId: "q_fallback", storeId: "store_fallback")],
            productsPermissions: nil
        )
        let gate = ProductsAsyncGate()
        productsService.onProducts = { await gate.wait() }

        async let staleLoad: [Qonversion.Product] = manager.products()
        await waitUntil { self.productsService.productsCallsCount >= 1 }
        manager.userDidChange()
        let otherUsersCatalog: [Qonversion.Product] = [makeProduct(qonversionId: "q_other_user", storeId: "store_other_user")]
        try localStorage.set(otherUsersCatalog, forKey: productsKey)
        await gate.open()

        let result: [Qonversion.Product] = try await staleLoad

        XCTAssertEqual(result.map(\.qonversionId), ["q_fallback"])
    }

    func testAPersistedProductWithoutAStoreIdIsReportedInTheLog() async throws {
        let messages = LogCollector()
        let sink: LoggerWrapper = LoggerWrapper(sink: { _, message in messages.append(message) })
        let manager = ProductsManager(
            apiKey: apiKey,
            productsService: productsService,
            storeKitFacade: storeKitFacade,
            localStorage: localStorage,
            fallbackService: fallbackService,
            logger: sink
        )
        let persisted: [Qonversion.Product] = [makeProduct(qonversionId: "q_persisted_no_store", storeId: "")]
        try localStorage.set(persisted, forKey: productsKey)
        productsService.error = QonversionError(type: .productsLoadingFailed)

        _ = try await manager.products()

        XCTAssertTrue(messages.all().contains { $0.contains("q_persisted_no_store") },
                      "an unpriceable product must be named on every path that serves it")
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

    func testAnEmptyMappingIsLoadedOnDemand() async {
        // A launch whose refresh failed (or never ran) must not leave the
        // offline entitlements calculation dead for the whole session.
        productsService.productPermissionsResult = ["pro": ["premium"]]

        let mapping: [String: [String]] = await manager.productPermissions()

        XCTAssertEqual(mapping, ["pro": ["premium"]])
        XCTAssertEqual(productsService.productPermissionsCallsCount, 1)
    }

    func testACachedMappingIsAnsweredWithoutARequest() async {
        productsService.productPermissionsResult = ["pro": ["premium"]]
        await manager.loadProductPermissions()

        let mapping: [String: [String]] = await manager.productPermissions()

        XCTAssertEqual(mapping, ["pro": ["premium"]])
        XCTAssertEqual(productsService.productPermissionsCallsCount, 1, "the cached mapping costs nothing")
    }

    func testAFailingMappingLoadIsNotRetriedOnEveryCall() async {
        // The reload is driven by demand: a permanently failing backend would
        // otherwise turn every entitlements check into a request.
        productsService.productPermissionsError = MockError.stubbed

        _ = await manager.productPermissions()
        _ = await manager.productPermissions()
        _ = await manager.productPermissions()

        XCTAssertEqual(productsService.productPermissionsCallsCount, 1)
    }

    func testConcurrentMappingLoadsShareOneRequest() async {
        productsService.productPermissionsResult = ["pro": ["premium"]]
        let gate = ProductsAsyncGate()
        productsService.onProductPermissions = { await gate.wait() }

        async let first: [String: [String]] = manager.productPermissions()
        await waitUntil { self.productsService.productPermissionsCallsCount >= 1 }
        async let second: [String: [String]] = manager.productPermissions()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await gate.open()

        let mappings: [[String: [String]]] = await [first, second]

        XCTAssertEqual(mappings, [["pro": ["premium"]], ["pro": ["premium"]]])
        XCTAssertEqual(productsService.productPermissionsCallsCount, 1)
    }

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
        XCTAssertNil(localStorage.data(forKey: productsKey), "the previous user's catalog must not be persisted for the new one")
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
            apiKey: "test_api_key",
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
        productsService.productsResult = [Qonversion.Product(qonversionId: "q", storeId: "s")]
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
        productsService.productsResult = [Qonversion.Product(qonversionId: "q", storeId: "s")]
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
        productsService.productsResult = [Qonversion.Product(qonversionId: "q", storeId: "s")]
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
