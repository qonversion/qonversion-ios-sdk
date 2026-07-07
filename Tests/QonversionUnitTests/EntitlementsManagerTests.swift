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
            from: Data(#"{"id": "QON_holder", "created": 1700000000, "environment": "production"}"#.utf8))
        manager = EntitlementsManager(
            entitlementsService: service,
            storeKitFacade: facade,
            productsManager: productsManager,
            userManager: userManager,
            userIdProvider: config,
            localStorage: storage,
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

    private func serverEntitlement(id: String, active: Bool = true) -> Qonversion.Entitlement {
        Qonversion.Entitlement(id: id, active: active, source: .appStore, startedDate: now, expirationDate: now.addingTimeInterval(3600))
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

    func testOtherErrorsAreRethrownWithoutLocalCalculation() async {
        service.error = QonversionError(type: .critical)          // 401/402/403
        setupLocalCalculationContext()

        do {
            _ = try await manager.entitlements()
            XCTFail("Expected the error to be rethrown")
        } catch { }

        XCTAssertTrue(facade.finishedTransactions.isEmpty)
    }

    func testGateFailureIsRethrownWithoutServiceCall() async {
        userManager.error = MockError.stubbed

        do {
            _ = try await manager.entitlements()
            XCTFail("Expected the gate error to be rethrown")
        } catch { }

        XCTAssertTrue(service.entitlementsCalls.isEmpty)
    }

    // MARK: - Local calculation persists to the same cache

    func testLocalCalculationResultIsPersisted() async throws {
        service.error = QonversionError(type: .internal)
        setupLocalCalculationContext()

        _ = try await manager.entitlements()

        // A fresh manager over the same storage sees the locally calculated
        // entitlement in its fallback chain even with no StoreKit data.
        facade.currentEntitlementsResult = []
        let recreated = EntitlementsManager(
            entitlementsService: service,
            storeKitFacade: facade,
            productsManager: productsManager,
            userManager: userManager,
            userIdProvider: config,
            localStorage: storage,
            logger: LoggerWrapper()
        )
        let entitlements = try await recreated.entitlements()

        XCTAssertEqual(entitlements["premium"]?.active, true)
    }
}
