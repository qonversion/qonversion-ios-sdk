//
//  PurchasesManagerTests.swift
//  QonversionUnitTests
//
//  Contract tests for the purchase and restore flows (TDD).
//
//  purchase(): user gate → store purchase → backend report → finish ONLY after
//  the backend confirmed → PurchaseResult with entitlements. On a 5xx /
//  connection report failure the purchase still SUCCEEDS with locally
//  calculated entitlements (production fault tolerance) and the transaction
//  stays unfinished. Observed out-of-band updates are reported, never finished.
//

import XCTest
@testable import Qonversion

final class PurchasesManagerTests: XCTestCase {

    private var service: MockPurchasesService!
    private var facade: MockStoreKitFacade!
    private var userManager: MockUserManager!
    private var entitlementsManager: MockEntitlementsManager!
    private var config: InternalConfig!
    private var manager: PurchasesManager!

    private let uid = "QON_buyer"

    override func setUp() {
        super.setUp()
        service = MockPurchasesService()
        facade = MockStoreKitFacade()
        userManager = MockUserManager()
        entitlementsManager = MockEntitlementsManager()
        config = InternalConfig(userId: uid)
        userManager.user = try? JSONDecoder.qonversionTest.decode(
            Qonversion.User.self,
            from: Data(#"{"id": "QON_buyer", "created": 1700000000, "environment": "production"}"#.utf8))
        manager = makeManager()
    }

    private func makeManager(launchMode: Qonversion.LaunchMode = .analytics) -> PurchasesManager {
        config.launchMode = launchMode
        return PurchasesManager(
            purchasesService: service,
            storeKitFacade: facade,
            userManager: userManager,
            entitlementsManager: entitlementsManager,
            userIdProvider: config,
            launchModeProvider: config,
            logger: LoggerWrapper()
        )
    }

    override func tearDown() {
        manager = nil
        config = nil
        entitlementsManager = nil
        userManager = nil
        facade = nil
        service = nil
        super.tearDown()
    }

    private func makeProduct(storeId: String = "com.app.pro") -> Qonversion.Product {
        Qonversion.Product(qonversionId: "pro", storeId: storeId, offeringId: nil)
    }

    private func makeTransaction(id: String, productId: String = "com.app.pro", purchaseDate: Date? = nil, jws: String? = "jws-proof") -> Qonversion.Transaction {
        Qonversion.Transaction(id: id, productId: productId, purchaseDate: purchaseDate, jws: jws)
    }

    private func entitlement(id: String) -> Qonversion.Entitlement {
        Qonversion.Entitlement(id: id, active: true, source: .appStore)
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - purchase happy path

    func testPurchaseGoesGateStorePurchaseReportFinishAndReturnsEntitlements() async throws {
        facade.purchaseResult = makeTransaction(id: "t1")
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        let result = try await manager.purchase(makeProduct(storeId: "com.app.pro"))

        XCTAssertEqual(userManager.obtainUserCallsCount, 1, "the user gate must be passed first")
        XCTAssertEqual(facade.purchasedStoreIds, ["com.app.pro"])
        XCTAssertEqual(service.sentTransactions.count, 1)
        XCTAssertEqual(service.sentTransactions.first?.userId, uid)
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["t1"], "finish only after the backend confirmed")
        XCTAssertEqual(result.transaction.id, "t1")
        XCTAssertEqual(result.entitlements.keys.sorted(), ["premium"])
    }

    func testPurchaseFinishHappensAfterReportNotBefore() async throws {
        facade.purchaseResult = makeTransaction(id: "t1")
        var finishedAtSendTime = false
        service.onSend = { [weak self] in
            finishedAtSendTime = !(self?.facade.finishedTransactions.isEmpty ?? true)
        }

        _ = try await manager.purchase(makeProduct())

        XCTAssertFalse(finishedAtSendTime, "the transaction must NOT be finished before the backend report")
        XCTAssertEqual(facade.finishedTransactions.count, 1)
    }

    // MARK: - purchase fault tolerance (production behavior)

    func testEligibleReportFailureSucceedsWithLocalEntitlementsAndNoFinish() async throws {
        facade.purchaseResult = makeTransaction(id: "t1")
        service.error = QonversionError(type: .internal)                       // 5xx
        entitlementsManager.localFallbackResult = ["premium": entitlement(id: "premium")]

        let result = try await manager.purchase(makeProduct())

        XCTAssertEqual(result.transaction.id, "t1")
        XCTAssertEqual(result.entitlements.keys.sorted(), ["premium"])
        XCTAssertEqual(entitlementsManager.localFallbackTransactions.first?.map(\.id), ["t1"])
        XCTAssertTrue(facade.finishedTransactions.isEmpty,
                      "an unreported transaction must stay unfinished so it can be re-reported later")
    }

    func testConnectionErrorOnReportAlsoSucceedsWithLocalEntitlements() async throws {
        facade.purchaseResult = makeTransaction(id: "t1")
        service.error = QonversionError(type: .invalidResponse, error: URLError(.timedOut))
        entitlementsManager.localFallbackResult = ["premium": entitlement(id: "premium")]

        let result = try await manager.purchase(makeProduct())

        XCTAssertEqual(result.entitlements.keys.sorted(), ["premium"])
    }

    func testNonEligibleReportFailureThrowsAndLeavesTransactionUnfinished() async {
        facade.purchaseResult = makeTransaction(id: "t1")
        service.error = MockError.stubbed

        do {
            _ = try await manager.purchase(makeProduct())
            XCTFail("Expected purchase to throw when the backend report fails non-eligibly")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseReportingFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(facade.finishedTransactions.isEmpty)
        XCTAssertTrue(entitlementsManager.localFallbackTransactions.isEmpty)
    }

    func testEntitlementsFetchFailureAfterSuccessfulReportFallsBackLocally() async throws {
        facade.purchaseResult = makeTransaction(id: "t1")
        entitlementsManager.entitlementsError = QonversionError(type: .critical)
        entitlementsManager.localFallbackResult = ["premium": entitlement(id: "premium")]

        let result = try await manager.purchase(makeProduct())

        XCTAssertEqual(result.entitlements.keys.sorted(), ["premium"],
                       "a reported purchase must not fail because of the entitlements fetch")
        XCTAssertEqual(facade.finishedTransactions.count, 1)
    }

    // MARK: - purchase failures

    func testPurchaseFailsWhenUserGateFails() async {
        userManager.error = MockError.stubbed

        do {
            _ = try await manager.purchase(makeProduct())
            XCTFail("Expected purchase to rethrow the gate error")
        } catch { }

        XCTAssertTrue(facade.purchasedStoreIds.isEmpty, "no store purchase without a backend user")
        XCTAssertTrue(service.sentTransactions.isEmpty)
    }

    func testPurchaseRethrowsStoreErrorWithoutReporting() async {
        facade.purchaseError = QonversionError(type: .purchaseCancelled)

        do {
            _ = try await manager.purchase(makeProduct())
            XCTFail("Expected purchase to rethrow the store error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseCancelled)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(service.sentTransactions.isEmpty)
        XCTAssertTrue(facade.finishedTransactions.isEmpty)
    }

    // MARK: - restore

    func testRestoreReportsLatestTransactionPerProductAndReturnsEntitlements() async throws {
        let older = makeTransaction(id: "old", purchaseDate: Date(timeIntervalSince1970: 1_600_000_000))
        let newer = makeTransaction(id: "new", purchaseDate: Date(timeIntervalSince1970: 1_700_000_000))
        facade.restoreResult = [older, newer]
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        let entitlements = try await manager.restore()

        XCTAssertEqual(userManager.obtainUserCallsCount, 1)
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["new"],
                       "only the latest transaction per product is reported")
        XCTAssertEqual(entitlements.keys.sorted(), ["premium"])
    }

    func testRestoreEligibleFailureSucceedsWithLocalEntitlements() async throws {
        facade.restoreResult = [makeTransaction(id: "t1")]
        service.error = QonversionError(type: .internal)
        entitlementsManager.localFallbackResult = ["premium": entitlement(id: "premium")]

        let entitlements = try await manager.restore()

        XCTAssertEqual(entitlements.keys.sorted(), ["premium"])
        XCTAssertEqual(entitlementsManager.localFallbackTransactions.first?.map(\.id), ["t1"])
    }

    func testRestoreNonEligibleFailureThrows() async {
        facade.restoreResult = [makeTransaction(id: "t1")]
        service.error = MockError.stubbed

        do {
            _ = try await manager.restore()
            XCTFail("Expected restore to throw")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .restoreFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - observed updates

    func testStartObservingStartsFacadeObservation() {
        manager.startObservingTransactions()

        XCTAssertEqual(facade.startObservingCallsCount, 1)
    }

    func testObservedUpdateIsReportedThroughGateAndNeverFinished() async {
        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { self.service.sentTransactions.count >= 1 }
        XCTAssertEqual(userManager.obtainUserCallsCount, 1)
        XCTAssertEqual(service.sentTransactions.first?.transaction.id, "u1")
        XCTAssertTrue(facade.finishedTransactions.isEmpty, "observed updates are never finished by the SDK")
    }

    func testObservedUpdateReportFailureIsSwallowed() async {
        service.error = MockError.stubbed

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { self.service.sentTransactions.count >= 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(facade.finishedTransactions.isEmpty)
    }

    // MARK: - unfinished transactions sweep at launch

    func testUnfinishedSweepDoesNothingInAnalyticsMode() async {
        // In Analytics mode the host app owns the transaction lifecycle.
        manager = makeManager(launchMode: .analytics)
        facade.unfinishedTransactionsResult = [makeTransaction(id: "t1")]

        await manager.processUnfinishedTransactions()

        XCTAssertEqual(facade.unfinishedTransactionsCallsCount, 0)
        XCTAssertTrue(service.sentTransactions.isEmpty)
        XCTAssertTrue(facade.finishedTransactions.isEmpty)
    }

    func testUnfinishedSweepReportsAndFinishesEachTransaction() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.unfinishedTransactionsResult = [makeTransaction(id: "t1"), makeTransaction(id: "t2", productId: "com.app.lite")]

        await manager.processUnfinishedTransactions()

        XCTAssertEqual(userManager.obtainUserCallsCount, 1, "the user gate must be passed before reporting")
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1", "t2"])
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["t1", "t2"])
    }

    func testUnfinishedSweepFinishesOnlyAfterReport() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.unfinishedTransactionsResult = [makeTransaction(id: "t1")]
        var finishedAtSendTime = false
        service.onSend = { [weak self] in
            finishedAtSendTime = !(self?.facade.finishedTransactions.isEmpty ?? true)
        }

        await manager.processUnfinishedTransactions()

        XCTAssertFalse(finishedAtSendTime, "finish only after the backend confirmed the report")
        XCTAssertEqual(facade.finishedTransactions.count, 1)
    }

    func testUnfinishedSweepReportFailureLeavesTransactionUnfinishedAndRetriable() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.unfinishedTransactionsResult = [makeTransaction(id: "t1")]
        service.error = MockError.stubbed

        await manager.processUnfinishedTransactions()

        XCTAssertTrue(facade.finishedTransactions.isEmpty)

        // The failed report must not poison the dedup: the next sweep retries.
        service.error = nil
        await manager.processUnfinishedTransactions()

        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1", "t1"])
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["t1"])
    }

    func testUnfinishedSweepUserGateFailureSkipsReporting() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.unfinishedTransactionsResult = [makeTransaction(id: "t1")]
        userManager.error = MockError.stubbed

        await manager.processUnfinishedTransactions()

        XCTAssertTrue(service.sentTransactions.isEmpty)
        XCTAssertTrue(facade.finishedTransactions.isEmpty)
    }

    // MARK: - sweep vs listener dedup

    func testObservedUpdateAlreadySweptIsNotReportedTwice() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        let transaction = makeTransaction(id: "t1")
        facade.unfinishedTransactionsResult = [transaction]

        await manager.processUnfinishedTransactions()
        // The same unfinished transaction arrives through Transaction.updates at launch.
        manager.transactionUpdated(transaction)

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1"], "the sweep and the listener must not double-report")
    }

    func testSweepSkipsTransactionAlreadyReportedByListener() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        let transaction = makeTransaction(id: "t1")
        facade.unfinishedTransactionsResult = [transaction]

        manager.transactionUpdated(transaction)
        await waitUntil { self.service.sentTransactions.count >= 1 }

        await manager.processUnfinishedTransactions()

        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1"])
    }
}
