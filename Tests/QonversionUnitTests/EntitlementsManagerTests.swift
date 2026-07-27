//
//  EntitlementsManagerTests.swift
//  QonversionUnitTests
//
//  entitlements(): gate → network → cache; on 5xx/connection errors — local
//  calculation over the cached mapping, merged with the cached entitlements,
//  persisted and returned. Other errors are rethrown (production behavior).
//

import XCTest
@testable import Qonversion

final class EntitlementsManagerTests: XCTestCase {

    private var service: MockEntitlementsService!
    private var facade: MockStoreKitFacade!
    private var productsManager: MockProductsManager!
    private var userManager: MockUserManager!
    private var storage: MockLocalStorage!
    private var config: InternalConfig!
    private var manager: EntitlementsManager!

    private let uid = "QON_holder"
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        service = MockEntitlementsService()
        facade = MockStoreKitFacade()
        productsManager = MockProductsManager()
        userManager = MockUserManager()
        storage = MockLocalStorage()
        config = InternalConfig(userId: uid)
        userManager.user = try? JSONDecoder.qonversionTest.decode(
            Qonversion.User.self,
            from: Data(#"{"id": "QON_holder", "created_at": "2023-11-14T22:13:20Z", "environment": "prod"}"#.utf8))
        manager = makeManager()
    }

    private func makeManager(cacheLifetime: TimeInterval = Qonversion.EntitlementsCacheLifetime.month.seconds) -> EntitlementsManager {
        EntitlementsManager(
            entitlementsService: service,
            storeKitFacade: facade,
            productsDataSource: productsManager,
            userManager: userManager,
            userIdProvider: config,
            localStorage: storage,
            cacheLifetime: cacheLifetime,
            logger: LoggerWrapper()
        )
    }

    override func tearDown() {
        manager = nil
        config = nil
        storage = nil
        userManager = nil
        productsManager = nil
        facade = nil
        service = nil
        super.tearDown()
    }

    /// A live entitlement: the expiration must stay in the future, otherwise
    /// the cache read drops it as stale (production parity).
    private func serverEntitlement(id: String, active: Bool = true) -> Qonversion.Entitlement {
        Qonversion.Entitlement(id: id, active: active, source: .appStore, startedDate: now, expirationDate: Date().addingTimeInterval(3600))
    }

    /// What the SDK actually hands to the host: with nothing to serve the
    /// call throws, which is the same observable outcome as "no access".
    private func servedEntitlements() async -> [String: Qonversion.Entitlement] {
        return (try? await manager.entitlements()) ?? [:]
    }

    private func setupLocalCalculationContext() {
        // A month subscription bought recently + mapping — the local path can grant "premium".
        var product = Qonversion.Product(qonversionId: "pro", storeId: "com.app.pro", offeringId: nil)
        product.subscription = Qonversion.Product.SubscriptionInfo(
            subscriptionGroupId: "g",
            subscriptionPeriod: Qonversion.Product.SubscriptionPeriod(unit: .month, value: 1)
        )
        productsManager.cachedProductsResult = [product]
        productsManager.cachedMapping = ["pro": ["premium"]]
        facade.currentEntitlementsResult = [
            Qonversion.Transaction(id: "t1", productId: "com.app.pro", purchaseDate: Date().addingTimeInterval(-3600))
        ]
    }

    // MARK: - Network success

    func testSuccessReturnsEntitlementsKeyedByIdAndCaches() async throws {
        service.entitlementsResult = [serverEntitlement(id: "premium"), serverEntitlement(id: "extra")]

        let entitlements = try await manager.entitlements()

        XCTAssertEqual(userManager.obtainUserCallsCount, 1)
        XCTAssertEqual(service.entitlementsCalls, [uid])
        XCTAssertEqual(Set(entitlements.keys), ["premium", "extra"])

        // Cached: a follow-up local-calculation path can read them back.
        service.error = QonversionError(type: .internal)
        setupLocalCalculationContext()
        let fallback = try await manager.entitlements()
        XCTAssertTrue(fallback.keys.contains("extra"), "cached server entitlements must participate in the fallback")
    }

    // MARK: - Local calculation eligibility

    func testInternalErrorTriggersLocalCalculation() async throws {
        service.error = QonversionError(type: .internal)          // 5xx
        setupLocalCalculationContext()

        let entitlements = try await manager.entitlements()

        XCTAssertEqual(entitlements["premium"]?.active, true)
        XCTAssertEqual(entitlements["premium"]?.source, .appStore)
    }

    func testConnectionErrorTriggersLocalCalculation() async throws {
        service.error = QonversionError(type: .invalidResponse, error: URLError(.notConnectedToInternet))
        setupLocalCalculationContext()

        let entitlements = try await manager.entitlements()

        XCTAssertEqual(entitlements["premium"]?.active, true)
    }

    func testAnyErrorIsAnsweredFromTheLocalFallbackWhenItHasSomethingToServe() async throws {
        // Production parity: the cache and the StoreKit calculation answer on
        // ANY launch failure — a 401/403/429 must not drop the user's access.
        service.error = QonversionError(type: .critical)          // 401/402/403
        setupLocalCalculationContext()

        let entitlements = try await manager.entitlements()

        XCTAssertEqual(entitlements["premium"]?.active, true)
        XCTAssertTrue(facade.finishedTransactions.isEmpty)
    }

    func testErrorIsRethrownWhenTheLocalFallbackHasNothingToServe() async {
        service.error = QonversionError(type: .critical)
        facade.currentEntitlementsResult = []

        do {
            _ = try await manager.entitlements()
            XCTFail("Expected the error to be rethrown when there is nothing to serve")
        } catch { }
    }

    func testGateFailureIsAnsweredFromTheLocalFallbackWithoutServiceCall() async throws {
        // The user gate must not short-circuit the fault-tolerance path: an
        // offline first call still has the cache and the store to answer from.
        userManager.error = MockError.stubbed
        setupLocalCalculationContext()

        let entitlements = try await manager.entitlements()

        XCTAssertEqual(entitlements["premium"]?.active, true)
        XCTAssertTrue(service.entitlementsCalls.isEmpty, "no request may go out without a backend user")
    }

    func testGateFailureIsRethrownWhenTheLocalFallbackIsEmpty() async {
        userManager.error = MockError.stubbed
        facade.currentEntitlementsResult = []

        do {
            _ = try await manager.entitlements()
            XCTFail("Expected the gate error to be rethrown")
        } catch { }

        XCTAssertTrue(service.entitlementsCalls.isEmpty)
    }

    // MARK: - expired cache revalidation

    func testCachedActiveEntitlementPastItsExpirationIsNotServed() async throws {
        let expired = Qonversion.Entitlement(
            id: "premium",
            active: true,
            source: .appStore,
            startedDate: now,
            expirationDate: Date().addingTimeInterval(-3600)
        )
        try storage.set(["premium": expired], forKey: "qonversion.keys.entitlements")
        storage.set(double: Date().timeIntervalSince1970, forKey: "qonversion.keys.entitlementsTimestamp")

        service.error = QonversionError(type: .internal)
        facade.currentEntitlementsResult = []

        let entitlements: [String: Qonversion.Entitlement] = await servedEntitlements()

        XCTAssertTrue(entitlements.isEmpty, "an entitlement claiming active past its expiration is stale")
    }

    // MARK: - user switch during the fetch

    func testEntitlementsOfThePreviousUserAreNotPersistedAfterASwitch() async throws {
        service.entitlementsResult = [serverEntitlement(id: "premium")]
        let gate = EntitlementsAsyncGate()
        service.onEntitlements = { await gate.wait() }

        async let staleFetch: [String: Qonversion.Entitlement] = manager.entitlements()
        try? await Task.sleep(nanoseconds: 50_000_000)
        manager.userDidChange()
        await gate.open()
        _ = try? await staleFetch

        let persisted: [String: Qonversion.Entitlement]? = try storage.object(
            forKey: "qonversion.keys.entitlements",
            dataType: [String: Qonversion.Entitlement].self
        )
        XCTAssertNil(persisted, "the previous user's entitlements must not be persisted for the new one")
    }

    func testLocalFallbackOfThePreviousUserIsNotPersistedAfterASwitch() async throws {
        service.error = QonversionError(type: .internal)
        setupLocalCalculationContext()
        let gate = EntitlementsAsyncGate()
        service.onEntitlements = { await gate.wait() }

        async let staleFetch: [String: Qonversion.Entitlement] = manager.entitlements()
        try? await Task.sleep(nanoseconds: 50_000_000)
        manager.userDidChange()
        await gate.open()
        _ = try? await staleFetch

        let persisted: [String: Qonversion.Entitlement]? = try storage.object(
            forKey: "qonversion.keys.entitlements",
            dataType: [String: Qonversion.Entitlement].self
        )
        XCTAssertNil(persisted, "the offline merge path must not leak the previous user's access")
    }

    // MARK: - Local calculation persists to the same cache

    func testLocalCalculationResultIsPersisted() async throws {
        service.error = QonversionError(type: .internal)
        setupLocalCalculationContext()

        _ = try await manager.entitlements()

        // A fresh manager over the same storage sees the locally calculated
        // entitlement in its fallback chain even with no StoreKit data.
        facade.currentEntitlementsResult = []
        let recreated = makeManager()
        let entitlements = try await recreated.entitlements()

        XCTAssertEqual(entitlements["premium"]?.active, true)
    }

    // MARK: - configured cache lifetime

    func testCacheOlderThanConfiguredLifetimeIsIgnoredInFallback() async throws {
        manager = makeManager(cacheLifetime: Qonversion.EntitlementsCacheLifetime.week.seconds)
        service.entitlementsResult = [serverEntitlement(id: "premium")]
        _ = try await manager.entitlements()

        // Age the cache beyond the configured week.
        storage.set(double: Date().timeIntervalSince1970 - 8 * 24 * 60 * 60, forKey: "qonversion.keys.entitlementsTimestamp")

        service.error = QonversionError(type: .internal)
        facade.currentEntitlementsResult = []
        let entitlements: [String: Qonversion.Entitlement] = await servedEntitlements()

        XCTAssertTrue(entitlements.isEmpty)
    }

    func testCacheWithinConfiguredLifetimeIsUsedInFallback() async throws {
        manager = makeManager(cacheLifetime: Qonversion.EntitlementsCacheLifetime.week.seconds)
        service.entitlementsResult = [serverEntitlement(id: "premium")]
        _ = try await manager.entitlements()

        storage.set(double: Date().timeIntervalSince1970 - 6 * 24 * 60 * 60, forKey: "qonversion.keys.entitlementsTimestamp")

        service.error = QonversionError(type: .internal)
        facade.currentEntitlementsResult = []
        let entitlements = try await manager.entitlements()

        XCTAssertTrue(entitlements.keys.contains("premium"))
    }

    // MARK: - User change

    func testUserDidChangeClearsPersistedEntitlementsCache() async throws {
        service.entitlementsResult = [serverEntitlement(id: "premium")]
        _ = try await manager.entitlements()

        manager.userDidChange()

        // Backend unreachable + no StoreKit data: without the cleanup the new
        // user would inherit the previous user's cached entitlements.
        service.error = QonversionError(type: .internal)
        facade.currentEntitlementsResult = []
        let entitlements: [String: Qonversion.Entitlement] = await servedEntitlements()

        XCTAssertTrue(entitlements.isEmpty)
    }
}

/// A reusable async gate: wait() suspends until open() is called.
private actor EntitlementsGateStorage {
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

private final class EntitlementsAsyncGate: @unchecked Sendable {
    private let storage = EntitlementsGateStorage()
    func open() async { await storage.open() }
    func wait() async { await storage.wait() }
}
