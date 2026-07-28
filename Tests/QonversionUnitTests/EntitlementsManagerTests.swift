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

    /// With nothing at all to serve the call must FAIL — an empty success
    /// would be indistinguishable from a genuine "no access" answer.
    private func assertNothingServed(
        _ expectedType: QonversionErrorType,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            let entitlements: [String: Qonversion.Entitlement] = try await manager.entitlements()
            XCTFail("Expected the error to surface, got \(entitlements)", file: file, line: line)
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, expectedType, file: file, line: line)
        } catch {
            XCTFail("Unexpected error type: \(error)", file: file, line: line)
        }
    }

    private func setupLocalCalculationContext() {
        // A month subscription bought recently + mapping — the local path can grant "premium".
        var product = Qonversion.Product(qonversionId: "pro", storeId: "com.app.pro")
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
        XCTAssertEqual(service.entitlementsCalls, [uid], "the fallback answers a FAILED request — it may not replace it")
    }

    func testErrorIsRethrownWhenTheLocalFallbackHasNothingToServe() async {
        service.error = QonversionError(type: .critical)
        facade.currentEntitlementsResult = []

        await assertNothingServed(.critical)
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
            let entitlements: [String: Qonversion.Entitlement] = try await manager.entitlements()
            XCTFail("Expected the gate error to be rethrown, got \(entitlements)")
        } catch {
            XCTAssertEqual(error as? MockError, MockError.stubbed, "the gate's own error must reach the caller unwrapped")
        }

        XCTAssertTrue(service.entitlementsCalls.isEmpty)
    }

    // MARK: - cache lifetime is measured from the last backend answer

    func testPermanentFailureCannotKeepTheCacheAliveForever() async throws {
        // The local fallback persists what it merged; refreshing the lifetime
        // timestamp there would mean an endlessly failing backend (revoked
        // key, permanent 401) keeps a lapsed user premium forever.
        manager = makeManager(cacheLifetime: Qonversion.EntitlementsCacheLifetime.week.seconds)
        service.entitlementsResult = [serverEntitlement(id: "premium")]
        _ = try await manager.entitlements()

        service.error = QonversionError(type: .critical)                        // permanent 401
        facade.currentEntitlementsResult = []

        // Six days in: still inside the lifetime, so the cached answer is
        // served — and that very call persists the merge result.
        let sixDaysAgo: TimeInterval = Date().timeIntervalSince1970 - 6 * 24 * 60 * 60
        storage.set(double: sixDaysAgo, forKey: "qonversion.keys.entitlementsBackendTimestamp")
        let served: [String: Qonversion.Entitlement] = await servedEntitlements()
        XCTAssertTrue(served.keys.contains("premium"))

        // The clock must keep running: serving from the cache is not a
        // backend answer and may not push the lifetime forward.
        XCTAssertEqual(storage.double(forKey: "qonversion.keys.entitlementsBackendTimestamp"), sixDaysAgo,
                       "a failing backend that keeps refreshing the lifetime would keep a lapsed user premium forever")

        // Two days later the lifetime has elapsed and the cache goes cold.
        storage.set(double: sixDaysAgo - 2 * 24 * 60 * 60, forKey: "qonversion.keys.entitlementsBackendTimestamp")

        await assertNothingServed(.critical)
    }

    func testBackendSuccessRefreshesTheLifetimeTimestamp() async throws {
        service.entitlementsResult = [serverEntitlement(id: "premium")]

        _ = try await manager.entitlements()

        let backendTimestamp: TimeInterval = storage.double(forKey: "qonversion.keys.entitlementsBackendTimestamp")
        XCTAssertGreaterThan(backendTimestamp, 0)
        XCTAssertLessThan(abs(backendTimestamp - Date().timeIntervalSince1970), 5)
    }

    func testLocalFallbackDoesNotRefreshTheLifetimeTimestamp() async throws {
        service.entitlementsResult = [serverEntitlement(id: "premium")]
        _ = try await manager.entitlements()
        let afterBackend: TimeInterval = storage.double(forKey: "qonversion.keys.entitlementsBackendTimestamp")

        service.error = QonversionError(type: .internal)
        setupLocalCalculationContext()
        let served: [String: Qonversion.Entitlement] = await servedEntitlements()

        // Without this the test cannot tell "the fallback ran and left the
        // clock alone" from "the call threw before touching it".
        XCTAssertEqual(served["premium"]?.active, true)
        XCTAssertEqual(storage.double(forKey: "qonversion.keys.entitlementsBackendTimestamp"), afterBackend)
    }

    // MARK: - provenance of the served entitlements

    func testResolvedEntitlementsReportTheBackendAsTheSource() async throws {
        service.entitlementsResult = [serverEntitlement(id: "premium")]

        let resolved = try await manager.resolvedEntitlements()

        XCTAssertEqual(resolved.source, .backend)
        XCTAssertEqual(resolved.entitlements.keys.sorted(), ["premium"])
    }

    func testResolvedEntitlementsReportTheLocalCalculationAsTheSource() async throws {
        // The fault-tolerance path answers successfully — the caller must
        // still be able to tell that the backend never spoke.
        service.error = QonversionError(type: .critical)
        setupLocalCalculationContext()

        let resolved = try await manager.resolvedEntitlements()

        XCTAssertEqual(resolved.source, .localCalculation)
        XCTAssertEqual(resolved.entitlements["premium"]?.active, true)
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

        await assertNothingServed(.internal)
    }

    func testALifetimeEntitlementWithAZeroExpirationSurvivesTheCacheFilter() async throws {
        // The zero-timestamp sentinel used to decode as 1970, and the
        // stale-entry filter then dropped a lifetime subscriber's access.
        let json = #"{"data": [{"id": "premium", "is_active": true, "source": "appstore", "expires_at": 0}]}"#
        let list = try JSONDecoder.qonversionTolerantTest.decode(Qonversion.EntitlementsList.self, from: Data(json.utf8))
        let cached: [String: Qonversion.Entitlement] = Dictionary(list.data.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        XCTAssertNil(cached["premium"]?.expirationDate)

        try storage.set(cached, forKey: "qonversion.keys.entitlements")
        storage.set(double: Date().timeIntervalSince1970, forKey: "qonversion.keys.entitlementsTimestamp")
        storage.set(double: Date().timeIntervalSince1970, forKey: "qonversion.keys.entitlementsBackendTimestamp")

        service.error = QonversionError(type: .internal)
        facade.currentEntitlementsResult = []

        let entitlements: [String: Qonversion.Entitlement] = await servedEntitlements()

        XCTAssertEqual(entitlements["premium"]?.active, true, "a lifetime entitlement must survive the stale-entry filter")
    }

    // MARK: - the expiry filter serves, it does not delete

    func testAnExpiredStripeEntitlementSurvivesInStorageAfterAnOfflineCycle() async throws {
        // The SDK can regenerate App Store entitlements from StoreKit, but
        // never stripe or manual ones. Persisting the FILTERED merge deleted
        // them for good the first time the backend was unreachable.
        let expiredStripe = Qonversion.Entitlement(id: "web_premium", active: true, source: .stripe, startedDate: now, expirationDate: Date().addingTimeInterval(-60))
        try storage.set(["web_premium": expiredStripe], forKey: "qonversion.keys.entitlements")
        storage.set(double: Date().timeIntervalSince1970, forKey: "qonversion.keys.entitlementsTimestamp")
        storage.set(double: Date().timeIntervalSince1970, forKey: "qonversion.keys.entitlementsBackendTimestamp")
        service.error = QonversionError(type: .internal)
        setupLocalCalculationContext()

        let served = try await manager.entitlements()

        XCTAssertNil(served["web_premium"], "an expired entitlement is not served")
        let persisted: [String: Qonversion.Entitlement]? = try storage.object(
            forKey: "qonversion.keys.entitlements",
            dataType: [String: Qonversion.Entitlement].self
        )
        XCTAssertNotNil(persisted?["web_premium"], "but it must still be there when the backend renews it")
    }

    // MARK: - the online fresh-cache short-circuit (ObjC parity)

    func testAFreshBackendCacheAnswersWithoutARequest() async throws {
        // QNProductCenterManager.m:594 answered from the cache while it was
        // younger than QNUtils' 5-minute default window; every gating check
        // costing a round trip is what that window exists to prevent.
        service.entitlementsResult = [serverEntitlement(id: "premium")]
        _ = try await manager.entitlements()
        XCTAssertEqual(service.entitlementsCalls.count, 1)

        let second = try await manager.entitlements()

        XCTAssertEqual(second["premium"]?.active, true)
        XCTAssertEqual(service.entitlementsCalls.count, 1, "a fresh cache must not cost a request")
    }

    func testACacheOlderThanTheFreshWindowIsRefreshed() async throws {
        try storage.set(["premium": serverEntitlement(id: "premium")], forKey: "qonversion.keys.entitlements")
        let stale: TimeInterval = Date().timeIntervalSince1970 - EntitlementsManager.freshCacheLifetime - 60
        storage.set(double: stale, forKey: "qonversion.keys.entitlementsTimestamp")
        storage.set(double: stale, forKey: "qonversion.keys.entitlementsBackendTimestamp")
        service.entitlementsResult = [serverEntitlement(id: "extra")]

        let result = try await manager.entitlements()

        XCTAssertEqual(service.entitlementsCalls.count, 1, "past the window the backend is authoritative again")
        XCTAssertEqual(result.keys.sorted(), ["extra"])
    }

    func testAFreshCacheWithAnExpiredActiveEntryIsRefreshed() async throws {
        // ObjC's second condition: an entitlement claiming to be active past
        // its own expiration means the cache no longer describes reality.
        let expired = Qonversion.Entitlement(id: "premium", active: true, source: .appStore, startedDate: now, expirationDate: Date().addingTimeInterval(-60))
        try storage.set(["premium": expired], forKey: "qonversion.keys.entitlements")
        storage.set(double: Date().timeIntervalSince1970, forKey: "qonversion.keys.entitlementsTimestamp")
        storage.set(double: Date().timeIntervalSince1970, forKey: "qonversion.keys.entitlementsBackendTimestamp")
        service.entitlementsResult = [serverEntitlement(id: "extra")]

        _ = try await manager.entitlements()

        XCTAssertEqual(service.entitlementsCalls.count, 1, "an expired-but-active entry must force a refresh")
    }

    func testALocallyCalculatedCacheDoesNotShortCircuitTheBackend() async throws {
        // Only a BACKEND answer opens the fresh window: a local calculation
        // must not stop the SDK from asking again.
        service.error = QonversionError(type: .internal)
        setupLocalCalculationContext()
        _ = try await manager.entitlements()
        service.error = nil
        service.entitlementsResult = [serverEntitlement(id: "premium")]

        _ = try await manager.entitlements()

        XCTAssertEqual(service.entitlementsCalls.count, 2, "the backend is asked again after a local fallback")
    }

    // MARK: - in-flight coalescing

    func testConcurrentCallsShareOneRequest() async throws {
        service.entitlementsResult = [serverEntitlement(id: "premium")]
        let gate = EntitlementsAsyncGate()
        service.onEntitlements = { await gate.wait() }

        async let first: [String: Qonversion.Entitlement] = manager.entitlements()
        async let second: [String: Qonversion.Entitlement] = manager.entitlements()
        async let third: [String: Qonversion.Entitlement] = manager.entitlements()
        try? await Task.sleep(nanoseconds: 100_000_000)
        await gate.open()
        let results: [[String: Qonversion.Entitlement]] = try await [first, second, third]

        XCTAssertEqual(service.entitlementsCalls.count, 1, "N concurrent gating checks must cost one request")
        XCTAssertEqual(results.map { $0.keys.sorted() }, [["premium"], ["premium"], ["premium"]])
    }

    func testAResolutionFinishingAfterAUserSwitchDoesNotEvictTheNewOne() async throws {
        // ABA on the single-flight slot: userDidChange() empties it out of
        // band while run A is still going, run B takes the empty slot, and A
        // then finishes. A must not wipe B out of the slot — a caller arriving
        // afterwards would start a THIRD concurrent resolution instead of
        // joining B, which is the single-flight silently degrading on every
        // identify/logout.
        service.entitlementsResult = [serverEntitlement(id: "premium")]
        let gateA = EntitlementsAsyncGate()
        let gateB = EntitlementsAsyncGate()
        service.onEntitlements = { await gateA.wait() }

        async let runA: [String: Qonversion.Entitlement] = manager.entitlements()
        try? await Task.sleep(nanoseconds: 100_000_000)

        manager.userDidChange()
        service.onEntitlements = { await gateB.wait() }
        async let runB: [String: Qonversion.Entitlement] = manager.entitlements()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(service.entitlementsCalls.count, 2, "the user switch must start a run of its own")

        // A fails on its way out: a successful A would be rejected by the
        // generation guard and re-resolve, adding a request this test does not
        // measure. What matters is only that A reaches its cleanup.
        let outdatedRunFailure = QonversionError(type: .internal)
        service.error = outdatedRunFailure
        await gateA.open()
        _ = try? await runA
        service.error = nil

        // The joining caller: B is still in flight, so this must cost nothing.
        async let runC: [String: Qonversion.Entitlement] = manager.entitlements()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(service.entitlementsCalls.count, 2, "the caller after the switch must join the run in flight, not start a third one")

        await gateB.open()
        _ = try? await runB
        _ = try? await runC
    }

    // MARK: - user switch during the fetch

    func testEntitlementsOfThePreviousUserAreNotPersistedAfterASwitch() async throws {
        service.entitlementsResult = [serverEntitlement(id: "premium")]
        let gate = EntitlementsAsyncGate()
        service.onEntitlements = { await gate.wait() }

        async let staleFetch: [String: Qonversion.Entitlement] = manager.entitlements()
        try? await Task.sleep(nanoseconds: 50_000_000)
        manager.userDidChange()
        // The re-resolve the rejected persist triggers answers for the NEW
        // user; the old user's entitlements must reach nobody.
        service.entitlementsResult = [serverEntitlement(id: "for-the-new-user")]
        await gate.open()
        let returned: [String: Qonversion.Entitlement]? = try? await staleFetch

        let persisted: [String: Qonversion.Entitlement]? = try storage.object(
            forKey: "qonversion.keys.entitlements",
            dataType: [String: Qonversion.Entitlement].self
        )
        XCTAssertNil(persisted?["premium"], "the previous user's entitlements must not be persisted for the new one")
        XCTAssertNil(returned?["premium"], "nor returned to the caller as if they were the new user's")
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

        // Age the cache beyond the configured week: the lifetime runs from
        // the last backend answer.
        storage.set(double: Date().timeIntervalSince1970 - 8 * 24 * 60 * 60, forKey: "qonversion.keys.entitlementsBackendTimestamp")

        service.error = QonversionError(type: .internal)
        facade.currentEntitlementsResult = []

        await assertNothingServed(.internal)
    }

    func testCacheWithinConfiguredLifetimeIsUsedInFallback() async throws {
        manager = makeManager(cacheLifetime: Qonversion.EntitlementsCacheLifetime.week.seconds)
        service.entitlementsResult = [serverEntitlement(id: "premium")]
        _ = try await manager.entitlements()

        storage.set(double: Date().timeIntervalSince1970 - 6 * 24 * 60 * 60, forKey: "qonversion.keys.entitlementsBackendTimestamp")

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

        await assertNothingServed(.internal)
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
