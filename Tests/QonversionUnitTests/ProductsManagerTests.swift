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
    private var userManager: MockUserManager!
    private var manager: ProductsManager!

    override func setUp() {
        super.setUp()
        productsService = MockProductsService()
        storeKitFacade = MockStoreKitFacade()
        localStorage = MockLocalStorage()
        fallbackService = MockFallbackService()
        userManager = MockUserManager()
        userManager.user = Qonversion.User(id: "user_abc")
        manager = makeManager()
    }

    private func makeManager() -> ProductsManager {
        let config = InternalConfig(userId: "user_abc")
        return ProductsManager(
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
        userManager = nil
        fallbackService = nil
        productsService = nil
        storeKitFacade = nil
        localStorage = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeProduct(qonversionId: String = "q_main", storeId: String = "store_main") -> Qonversion.Product {
        return Qonversion.Product(qonversionId: qonversionId, storeId: storeId, offeringId: nil)
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

    // Fixates current behavior: products without a matching store product are silently
    // skipped, so when the StoreKit facade returns no matching wrappers the manager
    // returns an EMPTY array even though the API returned products.
    func testProductsWithoutStoreMatchesReturnsEmptyArray() async throws {
        productsService.productsResult = [makeProduct()]
        // A wrapper with neither a StoreKit 2 product nor an SKProduct has a nil id,
        // so it can never match any storeId.
        storeKitFacade.productsResult = [StoreProductWrapper(_product: nil, oldProduct: nil)]

        let result = try await manager.products()

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(productsService.productsCallsCount, 1)
    }

    // Fixates current behavior: an empty enrichment result is assigned to loadedProducts,
    // which leaves the cache "empty", so the next call hits the service again.
    func testEmptyEnrichedResultIsNotCached() async throws {
        productsService.productsResult = [makeProduct()]
        storeKitFacade.productsResult = []

        _ = try await manager.products()
        _ = try await manager.products()

        XCTAssertEqual(productsService.productsCallsCount, 2)
        XCTAssertEqual(storeKitFacade.requestedProductIds.count, 2)
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

    // Fixates current behavior: the unenriched fallback result IS cached in memory,
    // so a subsequent call does not hit the service or StoreKit again.
    func testStoreKitErrorFallbackResultIsCached() async throws {
        productsService.productsResult = [makeProduct()]
        storeKitFacade.productsError = MockError.stubbed

        _ = try await manager.products()
        let second = try await manager.products()

        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(productsService.productsCallsCount, 1)
        XCTAssertEqual(storeKitFacade.requestedProductIds.count, 1)
    }

    // MARK: - Service error

    // Without a bundled fallback file, a products service error propagates to
    // the caller as-is and the injected local storage is never consulted.
    func testServiceErrorPropagatesWithoutDiskFallback() async {
        try? localStorage.set(Data([0x01]), forKey: "products")
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
