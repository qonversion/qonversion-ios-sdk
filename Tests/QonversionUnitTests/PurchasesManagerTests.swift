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
import StoreKit
@testable import Qonversion

final class PurchasesManagerTests: XCTestCase {

    private var service: MockPurchasesService!
    private var facade: MockStoreKitFacade!
    private var userManager: MockUserManager!
    private var entitlementsManager: MockEntitlementsManager!
    private var config: InternalConfig!
    private var localStorage: MockLocalStorage!
    private var manager: PurchasesManager!

    private let uid = "QON_buyer"

    override func setUp() {
        super.setUp()
        service = MockPurchasesService()
        facade = MockStoreKitFacade()
        userManager = MockUserManager()
        entitlementsManager = MockEntitlementsManager()
        config = InternalConfig(userId: uid)
        localStorage = MockLocalStorage()
        userManager.user = try? JSONDecoder.qonversionTest.decode(
            Qonversion.User.self,
            from: Data(#"{"id": "QON_buyer", "created_at": "2023-11-14T22:13:20Z", "environment": "prod"}"#.utf8))
        manager = makeManager()
    }

    private func makeManager(launchMode: Qonversion.LaunchMode = .analytics, reportsGate: TransactionReportsGate = TransactionReportsGate()) -> PurchasesManager {
        config.launchMode = launchMode
        return PurchasesManager(
            purchasesService: service,
            storeKitFacade: facade,
            userManager: userManager,
            entitlementsManager: entitlementsManager,
            userIdProvider: config,
            launchModeProvider: config,
            purchaseAssociationsStorage: PurchaseAssociationsStorage(localStorage: localStorage),
            localStorage: localStorage,
            reportsGate: reportsGate,
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
        Qonversion.Product(qonversionId: "pro", storeId: storeId)
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

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - purchase happy path

    func testEachFlowReportsWithItsOwnTrigger() async throws {
        // purchase
        facade.purchaseResult = makeTransaction(id: "trig-1")
        entitlementsManager.entitlementsResult = [:]
        _ = try await manager.purchase(makeProduct(), options: nil)
        XCTAssertEqual(service.sentTriggers, [.purchase])

        // restore
        facade.restoreResult = [makeTransaction(id: "trig-2")]
        _ = try await manager.restore()
        XCTAssertEqual(service.sentTriggers.last, .restore)

        // analytics ingestion
        await manager.handle(transactions: [makeTransaction(id: "trig-3")])
        XCTAssertEqual(service.sentTriggers.last, .handleStoreKit2Transactions)
    }

    func testSyncAndSweepReportWithTheirOwnTriggers() async throws {
        // historical data sync
        facade.historicalDataResult = [makeTransaction(id: "trig-4")]
        await manager.syncHistoricalData()
        XCTAssertEqual(service.sentTriggers.last, .syncHistoricalData)

        // unfinished transactions sweep
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.unfinishedTransactionsResult = [makeTransaction(id: "trig-5")]
        await manager.processUnfinishedTransactions()
        XCTAssertEqual(service.sentTriggers.last, .initialization)
    }

    func testPurchaseGoesGateStorePurchaseReportFinishAndReturnsEntitlements() async throws {
        manager = makeManager(launchMode: .subscriptionManagement)
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
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "t1")
        var finishedAtSendTime = false
        service.onSend = { [weak self] in
            finishedAtSendTime = !(self?.facade.finishedTransactions.isEmpty ?? true)
        }

        _ = try await manager.purchase(makeProduct())

        XCTAssertFalse(finishedAtSendTime, "the transaction must NOT be finished before the backend report")
        XCTAssertEqual(facade.finishedTransactions.count, 1)
    }

    func testPurchaseDoesNotFinishTheTransactionInAnalyticsMode() async throws {
        // In Analytics mode the host app owns the transaction lifecycle —
        // finishing it here would leave the app unable to process the purchase.
        manager = makeManager(launchMode: .analytics)
        facade.purchaseResult = makeTransaction(id: "t1")
        entitlementsManager.entitlementsResult = [:]

        _ = try await manager.purchase(makeProduct())

        XCTAssertEqual(service.sentTransactions.count, 1, "the purchase is still reported")
        XCTAssertTrue(facade.finishedTransactions.isEmpty)
    }

    func testPurchaseFinishesTheTransactionInSubscriptionManagementMode() async throws {
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "t1")
        entitlementsManager.entitlementsResult = [:]

        _ = try await manager.purchase(makeProduct())

        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["t1"])
    }

    func testPurchaseResultCarriesTheEntitlementsProvenance() async throws {
        // A locally computed answer must be distinguishable from a
        // backend-confirmed one.
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "t1")
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        entitlementsManager.entitlementsSource = .localCalculation

        let result = try await manager.purchase(makeProduct())

        XCTAssertEqual(result.entitlementsSource, .localCalculation)
    }

    func testPurchaseResultReportsTheBackendWhenItAnswered() async throws {
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "t1")
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        entitlementsManager.entitlementsSource = .backend

        let result = try await manager.purchase(makeProduct())

        XCTAssertEqual(result.entitlementsSource, .backend)
    }

    func testAnOfflinePurchaseReportsTheLocalCalculation() async throws {
        facade.purchaseResult = makeTransaction(id: "t1")
        service.error = QonversionError(type: .internal)
        entitlementsManager.localFallbackResult = ["premium": entitlement(id: "premium")]

        let result = try await manager.purchase(makeProduct())

        XCTAssertEqual(result.entitlementsSource, .localCalculation)
    }

    // MARK: - purchase options

    func testPurchaseForwardsOptionsToStoreAndReport() async throws {
        facade.purchaseResult = makeTransaction(id: "t1")
        let options = Qonversion.PurchaseOptions(quantity: 2, contextKeys: ["main"], screenUid: "screen_1")

        _ = try await manager.purchase(makeProduct(storeId: "com.app.pro"), options: options)

        XCTAssertEqual(facade.purchasedOptions.count, 1)
        XCTAssertEqual(facade.purchasedOptions.first?.quantity, 2)
        XCTAssertEqual(service.sentTransactions.first?.options?.contextKeys, ["main"])
        XCTAssertEqual(service.sentTransactions.first?.options?.screenUid, "screen_1")
    }

    func testPurchaseWithoutOptionsReportsWithoutOptions() async throws {
        facade.purchaseResult = makeTransaction(id: "t1")

        _ = try await manager.purchase(makeProduct())

        XCTAssertEqual(facade.purchasedOptions.first?.quantity, 1)
        XCTAssertNil(service.sentTransactions.first?.options ?? nil)
    }

    func testRestoreReportsWithoutOptions() async throws {
        facade.restoreResult = [makeTransaction(id: "t1")]

        _ = try await manager.restore()

        XCTAssertNil(service.sentTransactions.first?.options ?? nil)
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
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "t1")
        entitlementsManager.entitlementsError = QonversionError(type: .critical)
        entitlementsManager.localFallbackResult = ["premium": entitlement(id: "premium")]

        let result = try await manager.purchase(makeProduct())

        XCTAssertEqual(result.entitlements.keys.sorted(), ["premium"],
                       "a reported purchase must not fail because of the entitlements fetch")
        XCTAssertEqual(facade.finishedTransactions.count, 1)
    }

    // MARK: - a reported purchase invalidates the fresh entitlements window

    func testReportedPurchaseInvalidatesTheFreshWindowBeforeResolvingEntitlements() async throws {
        // The entitlements manager serves a cached backend answer for five
        // minutes; without this the result of a purchase made right after a
        // gating check carries the PRE-purchase entitlements.
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "t1")
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        _ = try await manager.purchase(makeProduct())

        XCTAssertEqual(entitlementsManager.invalidationCallsCount, 1)
        XCTAssertEqual(entitlementsManager.calls.first, .invalidateFreshBackendCache,
                       "the window must be closed before the result is resolved")
        XCTAssertTrue(entitlementsManager.calls.contains(.resolvedEntitlements))
    }

    func testFailedPurchaseReportDoesNotInvalidateTheFreshWindow() async throws {
        // Nothing reached the backend, so nothing there changed — the local
        // fallback path must stay exactly as it was.
        facade.purchaseResult = makeTransaction(id: "t1")
        service.error = QonversionError(type: .internal)
        entitlementsManager.localFallbackResult = ["premium": entitlement(id: "premium")]

        _ = try await manager.purchase(makeProduct())

        XCTAssertEqual(entitlementsManager.invalidationCallsCount, 0)
    }

    func testPurchaseThatDoesNotOwnTheReportDoesNotInvalidateTheFreshWindow() async throws {
        // Another flow owns the report of this transaction and invalidates
        // the window itself.
        let reportsGate = TransactionReportsGate()
        XCTAssertTrue(reportsGate.tryTake("t1"))
        manager = makeManager(launchMode: .subscriptionManagement, reportsGate: reportsGate)
        facade.purchaseResult = makeTransaction(id: "t1")
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        _ = try await manager.purchase(makeProduct())

        XCTAssertTrue(service.sentTransactions.isEmpty, "the report belongs to the other flow")
        XCTAssertEqual(entitlementsManager.invalidationCallsCount, 0)
    }

    func testRestoreInvalidatesTheFreshWindowAfterTheReport() async throws {
        facade.restoreResult = [makeTransaction(id: "t1")]
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        _ = try await manager.restore()

        XCTAssertEqual(entitlementsManager.invalidationCallsCount, 1)
        XCTAssertEqual(entitlementsManager.calls.first, .invalidateFreshBackendCache)
    }

    func testFailedRestoreReportDoesNotInvalidateTheFreshWindow() async throws {
        facade.restoreResult = [makeTransaction(id: "t1")]
        service.error = QonversionError(type: .internal)
        entitlementsManager.localFallbackResult = ["premium": entitlement(id: "premium")]

        _ = try await manager.restore()

        XCTAssertEqual(entitlementsManager.invalidationCallsCount, 0)
    }

    func testDeferredPurchaseDeliveryInvalidatesTheFreshWindowAfterTheReport() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.deferredPurchases())

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { await !collector.received.isEmpty }
        XCTAssertEqual(entitlementsManager.invalidationCallsCount, 1)
        XCTAssertEqual(entitlementsManager.calls.first, .invalidateFreshBackendCache,
                       "an Ask to Buy approval must be answered with post-report entitlements")
    }

    func testFailedDeferredPurchaseReportDoesNotInvalidateTheFreshWindow() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        service.error = QonversionError(type: .internal)
        entitlementsManager.localFallbackResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.deferredPurchases())

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { await !collector.received.isEmpty }
        XCTAssertEqual(entitlementsManager.invalidationCallsCount, 0)
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

    func testConcurrentPurchaseOfTheSameProductIsRefused() async throws {
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = [:]
        let gate = PurchasesAsyncGate()
        facade.purchaseResult = makeTransaction(id: "slow-1")
        facade.onPurchase = { await gate.wait() }

        async let first = manager.purchase(makeProduct(), options: nil)
        await waitUntil { self.facade.purchasedStoreIds.count >= 1 }

        do {
            _ = try await manager.purchase(makeProduct(), options: nil)
            XCTFail("Expected the second concurrent purchase to be refused")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseInProgress)
        }

        await gate.open()
        _ = try await first
        XCTAssertEqual(facade.purchasedStoreIds.count, 1, "one payment sheet per product")
    }

    func testEntitlementsUpdateEmittedBeforeSubscriptionIsBuffered() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        // The out-of-band transaction arrives before the host subscribes.
        await manager.transactionUpdated(makeTransaction(id: "early-1"))
        await waitUntil { !self.facade.finishedTransactions.isEmpty }

        let stream = manager.entitlementsUpdates()
        let consumer = Task { () -> [String: Qonversion.Entitlement]? in
            for await update in stream {
                return update
            }
            return nil
        }
        let timeout = Task { () -> [String: Qonversion.Entitlement]? in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            consumer.cancel()
            return nil
        }
        let received: [String: Qonversion.Entitlement]? = await consumer.value
        timeout.cancel()

        XCTAssertEqual(received?.keys.sorted(), ["premium"], "an Ask to Buy approval during launch must not be dropped")
    }

    // MARK: - report idempotency (review findings)

    func testPurchaseClaimsTheGateBeforeTheReportGoesOut() async throws {
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "race-1")
        entitlementsManager.entitlementsResult = [:]
        let gate = PurchasesAsyncGate()
        service.onSend = { await gate.wait() }

        async let purchase = manager.purchase(makeProduct(), options: nil)
        await waitUntil { self.service.sentTransactions.count >= 1 }

        // A restore racing the in-flight purchase report must skip the id.
        facade.restoreResult = [makeTransaction(id: "race-1")]
        async let restored = manager.restore()
        // Deterministic: the restore has passed the store call (and its gate
        // check happens right after) before the purchase report is released.
        await waitUntil { self.facade.facadeRestoreCallsCount >= 1 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        await gate.open()
        _ = try await purchase
        _ = try await restored

        XCTAssertEqual(service.sentTransactions.filter { $0.transaction.id == "race-1" }.count, 1,
                       "the same transaction must never be reported twice")
    }

    func testFailedPurchaseReportReleasesTheGateForRetries() async throws {
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "retry-1")
        service.error = URLError(.notConnectedToInternet)
        entitlementsManager.localFallbackResult = [:]
        _ = try await manager.purchase(makeProduct(), options: nil)

        service.error = nil
        entitlementsManager.entitlementsResult = [:]
        facade.unfinishedTransactionsResult = [makeTransaction(id: "retry-1")]
        await manager.processUnfinishedTransactions()

        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["retry-1", "retry-1"],
                       "the failed report must stay retriable by the sweep")
    }

    func testUserChangeResetsTheReportsGate() async throws {
        entitlementsManager.entitlementsResult = [:]
        facade.restoreResult = [makeTransaction(id: "shared-tx")]
        _ = try await manager.restore()
        XCTAssertEqual(service.sentTransactions.count, 1)

        manager.userDidChange()

        _ = try await manager.restore()

        XCTAssertEqual(service.sentTransactions.count, 2,
                       "after identify/logout the restore must attach the transactions to the new user")
    }

    // MARK: - restore single-flight

    func testConcurrentRestoresShareOneStoreRun() async throws {
        let gate = PurchasesAsyncGate()
        facade.onRestore = { await gate.wait() }
        entitlementsManager.entitlementsResult = [:]

        async let first: [String: Qonversion.Entitlement] = manager.restore()
        await waitUntil { self.facade.facadeRestoreCallsCount >= 1 }
        async let second: [String: Qonversion.Entitlement] = manager.restore()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await gate.open()
        _ = try await first
        _ = try await second

        XCTAssertEqual(facade.facadeRestoreCallsCount, 1, "concurrent restore() calls must join the in-flight run")
    }

    func testRestoreRunsAgainAfterTheFirstOneFinishes() async throws {
        entitlementsManager.entitlementsResult = [:]

        _ = try await manager.restore()
        _ = try await manager.restore()

        XCTAssertEqual(facade.facadeRestoreCallsCount, 2)
    }

    func testARestoreJoiningAFinishedRunStillSyncsWithTheStore() async throws {
        // Awaiting the run through joinedRestoreTask() — the entry point
        // restore() itself goes through — instead of through restore(), so the
        // slot is proven empty by the run's own cleanup rather than by
        // anything restore() does around it.
        entitlementsManager.entitlementsResult = [:]
        let run: Task<[String: Qonversion.Entitlement], Error> = manager.joinedRestoreTask()
        _ = try await run.value

        _ = try await manager.restore()

        XCTAssertEqual(facade.facadeRestoreCallsCount, 2, "restore() must always sync with the store")
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

    func testRestoredTransactionIsNotReReportedByTheListener() async throws {
        facade.restoreResult = [makeTransaction(id: "t1")]
        _ = try await manager.restore()

        manager.transactionUpdated(makeTransaction(id: "t1"))

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1"])
    }

    func testRestoreSkipsTransactionAlreadyReportedThisSession() async throws {
        let transaction = makeTransaction(id: "t1")
        manager.transactionUpdated(transaction)
        await waitUntil { self.service.sentTransactions.count >= 1 }

        facade.restoreResult = [transaction]
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let entitlements = try await manager.restore()

        XCTAssertEqual(service.sentTransactions.count, 1, "the backend already has this transaction")
        XCTAssertEqual(entitlements.keys.sorted(), ["premium"], "restore still returns entitlements")
    }

    // MARK: - observed updates in subscription-management mode (Ask to Buy / renewals)

    func testObservedUpdateInSubscriptionManagementModeIsFinishedAfterAck() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        var finishedAtSendTime = false
        service.onSend = { [weak self] in
            finishedAtSendTime = !(self?.facade.finishedTransactions.isEmpty ?? true)
        }

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { self.facade.finishedTransactions.count >= 1 }
        XCTAssertFalse(finishedAtSendTime, "finish only after the backend confirmed the report")
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["u1"], "in subscription-management mode the SDK owns the lifecycle")
    }

    func testObservedUpdateInSubscriptionManagementModeEmitsUpdatedEntitlements() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.entitlementsUpdates())

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        XCTAssertEqual(received.first?.keys.sorted(), ["premium"])
    }

    func testEveryEntitlementsUpdatesStreamReceivesTheUpdate() async {
        // Transaction.updates style: each access is an independent stream.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let first = StreamCollector(manager.entitlementsUpdates())
        let second = StreamCollector(manager.entitlementsUpdates())

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil {
            let firstEmpty = await first.received.isEmpty
            let secondEmpty = await second.received.isEmpty
            return !firstEmpty && !secondEmpty
        }
        let firstReceived = await first.received
        let secondReceived = await second.received
        XCTAssertEqual(firstReceived.count, 1)
        XCTAssertEqual(secondReceived.count, 1)
    }

    func testObservedUpdateReportFailureInSubscriptionManagementModeLeavesTransactionUnfinished() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        service.error = MockError.stubbed
        let collector = StreamCollector(manager.entitlementsUpdates())

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { self.service.sentTransactions.count >= 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(facade.finishedTransactions.isEmpty)
        let received = await collector.received
        XCTAssertTrue(received.isEmpty)
    }

    // MARK: - terminally rejected transactions (backend refused for good)

    private func rejectedError(statusCode: Int = 400) -> QonversionError {
        QonversionError(type: .unknown, additionalInfo: [ErrorConstants.statusCodeKey.rawValue: statusCode])
    }

    func testATerminallyRejectedTransactionIsNotFinishedInAnalyticsMode() async {
        manager = makeManager(launchMode: .analytics)
        service.error = rejectedError()

        manager.transactionUpdated(makeTransaction(id: "rejected-1"))

        await waitUntil { self.service.sentTransactions.count >= 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(facade.finishedTransactions.isEmpty, "Analytics mode never finishes a transaction the SDK did not purchase")
    }

    func testATerminallyRejectedTransactionIsFinishedInSubscriptionManagementMode() async {
        // An unfinished transaction is re-delivered by the store forever, and
        // a rejected report cannot ever succeed — it must be finished so the
        // store stops offering it back.
        manager = makeManager(launchMode: .subscriptionManagement)
        service.error = rejectedError()

        manager.transactionUpdated(makeTransaction(id: "rejected-1"))

        await waitUntil { !self.facade.finishedTransactions.isEmpty }
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["rejected-1"])
    }

    func testATerminallyRejectedTransactionIsNotReReportedOnRedelivery() async {
        manager = makeManager(launchMode: .analytics)
        service.error = rejectedError()
        manager.transactionUpdated(makeTransaction(id: "rejected-1"))
        await waitUntil { self.service.sentTransactions.count >= 1 }

        // The store re-delivers the still-unfinished transaction on the next
        // launch (or the listener fires again for the same one).
        manager.transactionUpdated(makeTransaction(id: "rejected-1"))
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(service.sentTransactions.count, 1, "a terminally rejected transaction must not be posted again")
    }

    func testANonTerminalReportFailureRemainsRetriableUnlikeARejection() async {
        manager = makeManager(launchMode: .analytics)
        service.error = URLError(.notConnectedToInternet)
        manager.transactionUpdated(makeTransaction(id: "offline-1"))
        await waitUntil { self.service.sentTransactions.count >= 1 }

        service.error = nil
        manager.transactionUpdated(makeTransaction(id: "offline-1"))
        await waitUntil { self.service.sentTransactions.count >= 2 }

        XCTAssertEqual(service.sentTransactions.count, 2, "an offline failure must stay retriable, unlike a terminal rejection")
    }

    func testUserChangeForgetsRejectedTransactionsSoTheNewUsersAttemptIsNotSkipped() async {
        manager = makeManager(launchMode: .analytics)
        service.error = rejectedError()
        manager.transactionUpdated(makeTransaction(id: "rejected-1"))
        await waitUntil { self.service.sentTransactions.count >= 1 }

        manager.userDidChange()
        service.error = nil
        manager.transactionUpdated(makeTransaction(id: "rejected-1"))

        await waitUntil { self.service.sentTransactions.count >= 2 }
        XCTAssertEqual(service.sentTransactions.count, 2, "the previous user's rejection must not skip the new user's own attempt")
    }

    // MARK: - deferred purchases (Ask to Buy / SCA parity)

    func testDeferredPurchaseIsEmittedInAnalyticsModeWithoutFinishing() async {
        // The approval of a pending purchase must reach the host in BOTH
        // modes — only the transaction lifecycle differs.
        manager = makeManager(launchMode: .analytics)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.deferredPurchases())

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        XCTAssertEqual(received.first?.transaction.id, "u1")
        XCTAssertEqual(received.first?.entitlements.keys.sorted(), ["premium"])
        XCTAssertEqual(received.first?.entitlementsSource, .backend)
        XCTAssertTrue(facade.finishedTransactions.isEmpty, "the host app owns the lifecycle in Analytics mode")
    }

    func testDeferredPurchaseIsEmittedInSubscriptionManagementMode() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.deferredPurchases())

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        XCTAssertEqual(received.first?.transaction.id, "u1")
        XCTAssertEqual(received.first?.entitlementsSource, .backend)
        await waitUntil { !self.facade.finishedTransactions.isEmpty }
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["u1"])
    }

    func testDeferredPurchaseIsEmittedWithLocalEntitlementsWhenTheReportFails() async {
        // An unreachable backend must not swallow the approval: production
        // calculates the entitlements locally and still notifies the host.
        manager = makeManager(launchMode: .subscriptionManagement)
        service.error = QonversionError(type: .internal)                       // 5xx
        entitlementsManager.localFallbackResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.deferredPurchases())

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        XCTAssertEqual(received.first?.entitlements.keys.sorted(), ["premium"])
        XCTAssertEqual(received.first?.entitlementsSource, .localCalculation)
        XCTAssertEqual(entitlementsManager.localFallbackTransactions.first?.map(\.id), ["u1"])
        XCTAssertTrue(facade.finishedTransactions.isEmpty, "an unreported transaction stays unfinished")
    }

    func testDeferredPurchaseOfAConsumableIsIdentifiableWithoutEntitlements() async {
        // A consumable grants no entitlement: without the transaction in the
        // signal the host could not tell that anything happened at all.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = [:]
        let collector = StreamCollector(manager.deferredPurchases())

        manager.transactionUpdated(makeTransaction(id: "coins-1", productId: "com.app.coins"))

        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        XCTAssertEqual(received.first?.transaction.id, "coins-1")
        XCTAssertEqual(received.first?.transaction.productId, "com.app.coins")
        XCTAssertTrue(received.first?.entitlements.isEmpty ?? false)
    }

    func testDeferredPurchaseLabelsLocallyCalculatedEntitlementsAsSuch() async {
        // The report reached the backend, but the entitlements request did
        // not: the entitlements manager answers from its fault-tolerance
        // path, and labelling that as .backend would be a lie.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        entitlementsManager.entitlementsSource = .localCalculation
        let collector = StreamCollector(manager.deferredPurchases())

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        XCTAssertEqual(received.first?.entitlementsSource, .localCalculation)
    }

    // MARK: - the host sees every purchase exactly once

    func testTransactionAlreadySurfacedInAPreviousSessionIsReportedButNotEmitted() async {
        // Transaction.updates redelivers every unfinished transaction on each
        // cold start; in Analytics mode nothing is ever finished, so without
        // this gate the host would get ancient purchases as fresh ones on
        // every launch.
        manager = makeManager(launchMode: .analytics)
        try? localStorage.set(["old-1"], forKey: "qonversion.keys.surfacedTransactions")
        manager = makeManager(launchMode: .analytics)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.deferredPurchases())

        manager.transactionUpdated(makeTransaction(id: "old-1"))

        await waitUntil { self.service.sentTransactions.count >= 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["old-1"], "reporting is unchanged")
        let received = await collector.received
        XCTAssertTrue(received.isEmpty, "the host has already seen this purchase")
    }

    func testNewTransactionIsEmittedOnceAndNotAgainOnRedelivery() async {
        manager = makeManager(launchMode: .analytics)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.deferredPurchases())

        manager.transactionUpdated(makeTransaction(id: "fresh-1"))
        await waitUntil { await !collector.received.isEmpty }

        // The next cold start re-delivers the same unfinished transaction to
        // a brand new manager over the same storage.
        let relaunched: PurchasesManager = makeManager(launchMode: .analytics)
        let relaunchedCollector = StreamCollector(relaunched.deferredPurchases())
        relaunched.transactionUpdated(makeTransaction(id: "fresh-1"))
        try? await Task.sleep(nanoseconds: 200_000_000)

        let received = await collector.received
        let receivedAfterRelaunch = await relaunchedCollector.received
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(receivedAfterRelaunch.isEmpty, "a purchase the host already saw must not come back on the next launch")
    }

    func testSynchronousPurchaseWithAFailedReportIsNotReSurfacedAsDeferred() async throws {
        // The purchase answered its caller directly; the failed report
        // releases the dedup gate, so the updates listener may pick the same
        // transaction up — the host must not be told about it twice.
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "p1")
        service.error = QonversionError(type: .internal)                       // 5xx
        entitlementsManager.localFallbackResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.deferredPurchases())

        _ = try await manager.purchase(makeProduct())
        service.error = nil
        manager.transactionUpdated(makeTransaction(id: "p1"))
        try? await Task.sleep(nanoseconds: 200_000_000)

        let received = await collector.received
        XCTAssertTrue(received.isEmpty, "the caller already got this transaction as a purchase result")
    }

    func testAPurchaseWhoseReportWasRejectedIsStillSurfacedOnRedelivery() async {
        // A rejected report (422 / 400 — nothing the local fallback may
        // answer) makes purchase() THROW: the host got an exception, not a
        // PurchaseResult, so it never learned about the transaction. Marking
        // it surfaced before the report means the store's next delivery of the
        // same unfinished transaction is swallowed as "already seen".
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "p1")
        service.error = QonversionError(type: .receiptValidationError)
        let collector = StreamCollector(manager.deferredPurchases())

        do {
            _ = try await manager.purchase(makeProduct())
            XCTFail("Expected the rejected report to throw")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseReportingFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        service.error = nil
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        manager.transactionUpdated(makeTransaction(id: "p1"))
        await waitUntil { await !collector.received.isEmpty }

        let received: [Qonversion.DeferredPurchase] = await collector.received
        XCTAssertEqual(received.map(\.transaction.id), ["p1"], "a purchase the host was never handed must still reach it")
    }

    func testMoreUnfinishedTransactionsThanTheSurfacedLimitAreNotRepeatedOnTheNextLaunch() async {
        // Analytics mode finishes nothing, so the store hands the whole
        // unfinished set back on every cold start. A surfaced set that evicts
        // its oldest ids at a fixed limit forgets the transactions above it and
        // re-delivers them as fresh purchases, launch after launch.
        manager = makeManager(launchMode: .analytics)
        entitlementsManager.entitlementsResult = [:]
        let total = 250
        let transactions: [Qonversion.Transaction] = (1...total).map {
            makeTransaction(id: "t\($0)", productId: "com.app.consumable")
        }
        facade.unfinishedTransactionsResult = transactions
        let collector = StreamCollector(manager.deferredPurchases())

        await manager.processUnfinishedTransactions()
        await waitUntil(timeout: 20.0) { await collector.received.count >= total }
        let firstLaunch: [Qonversion.DeferredPurchase] = await collector.received
        XCTAssertEqual(firstLaunch.count, total, "every unfinished transaction reaches the host once")

        // The next cold start: a fresh manager over the same storage, handed
        // the very same unfinished set.
        let relaunched: PurchasesManager = makeManager(launchMode: .analytics)
        let relaunchedCollector = StreamCollector(relaunched.deferredPurchases())

        await relaunched.processUnfinishedTransactions()
        // A transaction the listener DOES surface marks the point where the
        // sweep's emissions, if any, would already have arrived.
        relaunched.transactionUpdated(makeTransaction(id: "marker", productId: "com.app.lite"))
        await waitUntil(timeout: 20.0) { await !relaunchedCollector.received.isEmpty }

        let secondLaunch: [Qonversion.DeferredPurchase] = await relaunchedCollector.received
        XCTAssertEqual(secondLaunch.map(\.transaction.id), ["marker"],
                       "no purchase the host already saw may come back, however many are unfinished")
    }

    func testAnObservedTransactionOfAnInFlightPurchaseIsNotDeliveredTwice() async throws {
        // StoreKit may hand the same transaction to the updates listener while
        // the purchase call is still inside the payment sheet. The purchase
        // answers its caller with a PurchaseResult in every branch, so the
        // listener steps aside — and it steps aside BEFORE touching the
        // transaction: no report, no finish, nothing claimed while the sheet
        // is still up.
        manager = makeManager(launchMode: .subscriptionManagement)
        let transaction: Qonversion.Transaction = makeTransaction(id: "p1")
        facade.purchaseResult = transaction
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.deferredPurchases())
        var touchedDuringTheSheet = true

        facade.onPurchase = { [weak self] in
            guard let self else { return }
            self.manager.transactionUpdated(transaction)
            // Long enough for the listener task to have run to completion.
            try? await Task.sleep(nanoseconds: 200_000_000)
            touchedDuringTheSheet = !self.facade.finishedTransactions.isEmpty || !self.service.sentTransactions.isEmpty
        }

        let result: Qonversion.PurchaseResult = try await manager.purchase(makeProduct())

        XCTAssertFalse(touchedDuringTheSheet, "the listener must step aside before reporting or finishing")
        XCTAssertEqual(result.transaction.id, "p1")
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["p1"], "the purchase reports it exactly once")
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["p1"], "the purchase finishes it exactly once")
        let received = await collector.received
        XCTAssertTrue(received.isEmpty, "the caller gets this transaction as the purchase result")
    }

    func testATransactionSteppedAsideForAFailedPurchaseIsSurfacedOnRedelivery() async {
        // An Ask to Buy approval for product X lands while purchase(X) is in
        // flight, and the user then cancels the sheet. The listener stepped
        // aside, so the approval must still be intact: unreported, unfinished
        // and unsurfaced — and the store's next delivery of it reaches the
        // host as a deferred purchase.
        manager = makeManager(launchMode: .subscriptionManagement)
        let transaction: Qonversion.Transaction = makeTransaction(id: "p1")
        facade.purchaseError = QonversionError(type: .purchaseCancelled)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.deferredPurchases())

        facade.onPurchase = { [weak self] in
            guard let self else { return }
            self.manager.transactionUpdated(transaction)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        do {
            _ = try await manager.purchase(makeProduct())
            XCTFail("Expected the cancelled purchase to throw")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseCancelled)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(service.sentTransactions.isEmpty, "a stepped-aside transaction must stay unreported")
        XCTAssertTrue(facade.finishedTransactions.isEmpty, "a finished transaction never comes back — it must stay unfinished")

        // The store re-delivers it, now with nothing in flight.
        manager.transactionUpdated(transaction)
        await waitUntil { await !collector.received.isEmpty }

        let received: [Qonversion.DeferredPurchase] = await collector.received
        XCTAssertEqual(received.map(\.transaction.id), ["p1"], "the approval must still reach the host")
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["p1"])
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["p1"])
    }

    // MARK: - revocations (refund, family sharing revocation)

    private func makeRevokedTransaction(id: String, productId: String = "com.app.pro") -> Qonversion.Transaction {
        let revocationDate = Date(timeIntervalSince1970: 1_700_000_000)

        return Qonversion.Transaction(id: id, productId: productId, purchaseDate: nil, jws: "jws-proof", revocationDate: revocationDate)
    }

    func testRevokedTransactionEmitsUpdatedEntitlementsEvenWhenItsIdIsAlreadySurfaced() async {
        // StoreKit delivers a refund as the SAME transaction id that was
        // reported and surfaced when it was bought — both dedup gates already
        // hold it, and both would swallow the revocation.
        let gate = TransactionReportsGate()
        _ = gate.tryTake("t1")
        try? localStorage.set(["t1"], forKey: "qonversion.keys.surfacedTransactions")
        manager = makeManager(launchMode: .subscriptionManagement, reportsGate: gate)
        entitlementsManager.entitlementsResult = [:]
        let collector = StreamCollector(manager.entitlementsUpdates())

        manager.transactionUpdated(makeRevokedTransaction(id: "t1"))

        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(received.first?.isEmpty ?? false, "the host must learn that the entitlement is gone")
        XCTAssertTrue(entitlementsManager.calls.contains(.invalidateFreshBackendCache),
                      "the cached answer predates the revocation")
    }

    func testRevokedTransactionIsNotReportedAsAPurchase() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = [:]
        let collector = StreamCollector(manager.entitlementsUpdates())

        manager.transactionUpdated(makeRevokedTransaction(id: "r1"))

        await waitUntil { await !collector.received.isEmpty }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(service.sentTransactions.isEmpty, "the App Store server already told the backend about the refund")
    }

    func testRevokedTransactionEmitsNoDeferredPurchase() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = [:]
        let purchases = StreamCollector(manager.deferredPurchases())
        let updates = StreamCollector(manager.entitlementsUpdates())

        manager.transactionUpdated(makeRevokedTransaction(id: "r1"))

        await waitUntil { await !updates.received.isEmpty }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let received = await purchases.received
        XCTAssertTrue(received.isEmpty, "a refund is not a purchase")
    }

    func testRevokedTransactionSeenByTheLaunchSweepEmitsUpdatedEntitlements() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = [:]
        facade.unfinishedTransactionsResult = [makeRevokedTransaction(id: "r1")]
        let collector = StreamCollector(manager.entitlementsUpdates())

        await manager.processUnfinishedTransactions()

        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(service.sentTransactions.isEmpty, "a revocation is never reported as a purchase")
    }

    func testRevokedTransactionIsFinishedInSubscriptionManagementMode() async {
        // An unfinished revocation is re-delivered by the store on every launch.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = [:]

        manager.transactionUpdated(makeRevokedTransaction(id: "r1"))

        await waitUntil { !self.facade.finishedTransactions.isEmpty }
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["r1"])
    }

    func testRevokedTransactionIsNotFinishedInAnalyticsMode() async {
        manager = makeManager(launchMode: .analytics)
        entitlementsManager.entitlementsResult = [:]
        let collector = StreamCollector(manager.entitlementsUpdates())

        manager.transactionUpdated(makeRevokedTransaction(id: "r1"))

        await waitUntil { await !collector.received.isEmpty }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(facade.finishedTransactions.isEmpty, "the host app owns the lifecycle in Analytics mode")
    }

    func testARevocationStaysReadableByAStreamCreatedAfterIt() async {
        // A revocation travels the same snapshot channel as a deferred
        // purchase's entitlements, and a snapshot is replayed state: a screen
        // that subscribes later must still read the access that is now gone.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = [:]
        let first = StreamCollector(manager.entitlementsUpdates())

        manager.transactionUpdated(makeRevokedTransaction(id: "late-1"))
        await waitUntil { await !first.received.isEmpty }

        let second = StreamCollector(manager.entitlementsUpdates())

        await waitUntil { await !second.received.isEmpty }
        let received: [[String: Qonversion.Entitlement]] = await second.received
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(received.first?.isEmpty ?? false, "the first subscription must not consume the revocation snapshot")
    }

    func testARevocationAlreadyAccountedForIsNotProcessedAgainOnTheNextLaunch() async {
        // Analytics mode never finishes the transaction, so the store hands
        // the very same revocation over again on every launch.
        manager = makeManager(launchMode: .analytics)
        entitlementsManager.entitlementsResult = [:]
        let first = StreamCollector(manager.entitlementsUpdates())

        manager.transactionUpdated(makeRevokedTransaction(id: "twice-1"))
        await waitUntil { await !first.received.isEmpty }

        let surfaced: [String]? = try? localStorage.object(forKey: "qonversion.keys.surfacedTransactions", dataType: [String].self)
        XCTAssertEqual(surfaced, ["revoked:twice-1"], "the revocation is recorded under a namespace of its own")

        // "Next launch": a fresh manager over the same storage.
        let relaunched: PurchasesManager = makeManager(launchMode: .analytics)
        let second = StreamCollector(relaunched.entitlementsUpdates())
        relaunched.transactionUpdated(makeRevokedTransaction(id: "twice-1"))

        try? await Task.sleep(nanoseconds: 200_000_000)
        let received: [[String: Qonversion.Entitlement]] = await second.received
        XCTAssertTrue(received.isEmpty, "a revocation the SDK already accounted for must not be republished")
        XCTAssertEqual(entitlementsManager.invalidationCallsCount, 1, "the fresh window is invalidated once, by the launch that saw the refund")
    }

    func testTheBufferedLaunchEmissionReachesBothStreams() async {
        // The backlog exists for hosts that subscribe after launch; the
        // entitlements projection must not steal it from deferredPurchases.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        manager.transactionUpdated(makeTransaction(id: "early-1"))
        await waitUntil { !self.facade.finishedTransactions.isEmpty }

        let projection = StreamCollector(manager.entitlementsUpdates())
        let purchases = StreamCollector(manager.deferredPurchases())

        await waitUntil {
            let projectionEmpty = await projection.received.isEmpty
            let purchasesEmpty = await purchases.received.isEmpty
            return !projectionEmpty && !purchasesEmpty
        }
        let receivedEntitlements = await projection.received
        let receivedPurchases = await purchases.received
        XCTAssertEqual(receivedEntitlements.first?.keys.sorted(), ["premium"])
        XCTAssertEqual(receivedPurchases.first?.transaction.id, "early-1")
    }

    func testALiveEntitlementsSubscriberDoesNotConsumeTheBacklogOfALaterSubscriber() async {
        // The exact shape the Sample and the README show: the host subscribes
        // to entitlementsUpdates() first and KEEPS the stream alive, then
        // subscribes to deferredPurchases() later. The launch backlog must
        // still be waiting for the second subscription.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        let projection = StreamCollector(manager.entitlementsUpdates())
        // Let the projection actually attach before the launch emission.
        try? await Task.sleep(nanoseconds: 100_000_000)

        manager.transactionUpdated(makeTransaction(id: "early-1"))
        await waitUntil { !self.facade.finishedTransactions.isEmpty }
        await waitUntil { await !projection.received.isEmpty }

        let purchases = StreamCollector(manager.deferredPurchases())

        await waitUntil { await !purchases.received.isEmpty }
        let received = await purchases.received
        XCTAssertEqual(received.first?.transaction.id, "early-1")
        let projectionReceived = await projection.received
        XCTAssertEqual(projectionReceived.count, 1, "the live subscriber must not be replayed its own value")
    }

    func testAProjectionThatIsNeverIteratedDoesNotConsumeTheBacklog() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        // Created and dropped without iterating — a host may build the stream
        // long before it starts consuming it.
        _ = manager.entitlementsUpdates()

        manager.transactionUpdated(makeTransaction(id: "early-1"))
        await waitUntil { !self.facade.finishedTransactions.isEmpty }

        let purchases = StreamCollector(manager.deferredPurchases())

        await waitUntil { await !purchases.received.isEmpty }
        let received = await purchases.received
        XCTAssertEqual(received.first?.transaction.id, "early-1")
    }

    func testEntitlementsUpdatesProjectsTheDeferredPurchaseEntitlements() async {
        manager = makeManager(launchMode: .analytics)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.entitlementsUpdates())

        manager.transactionUpdated(makeTransaction(id: "u1"))

        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        XCTAssertEqual(received.first?.keys.sorted(), ["premium"])
    }

    func testTheEntitlementsProjectionIsBoundedLikeItsSubscription() async {
        // A host that builds the projection and stops reading it must not turn
        // it into an unbounded queue: the subscription it wraps keeps only the
        // newest values, and the projection must keep exactly as many.
        manager = makeManager(launchMode: .analytics)
        let bufferSize: Int = AsyncMulticast<Qonversion.DeferredPurchase>.subscriberBufferSize
        let emissions: Int = bufferSize + 5
        // Subscribed here, iterated only at the end.
        let projection: AsyncStream<[String: Qonversion.Entitlement]> = manager.entitlementsUpdates()
        let purchases = StreamCollector(manager.deferredPurchases())

        for index in 0..<emissions {
            entitlementsManager.entitlementsResult = ["e\(index)": entitlement(id: "e\(index)")]
            manager.transactionUpdated(makeTransaction(id: "buffered-\(index)"))
            await waitUntil { await purchases.received.count >= index + 1 }
        }

        let collector = StreamCollector(projection)
        await waitUntil { await collector.received.last?.keys.first == "e\(emissions - 1)" }

        let received: [[String: Qonversion.Entitlement]] = await collector.received
        XCTAssertEqual(received.count, bufferSize, "the projection must drop the oldest values, not queue them all")
    }

    // MARK: - deferred purchases are delivered exactly once

    func testAPurchaseTheHostReceivedIsNotHandedToALaterSubscription() async {
        // The documented SwiftUI shape: a screen that re-appears builds a
        // second subscription. Handing it the same approval again would grant
        // the content twice.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let first = StreamCollector(manager.deferredPurchases())

        manager.transactionUpdated(makeTransaction(id: "once-1"))
        await waitUntil { await !first.received.isEmpty }

        let second = StreamCollector(manager.deferredPurchases())
        try? await Task.sleep(nanoseconds: 200_000_000)

        let firstReceived: [Qonversion.DeferredPurchase] = await first.received
        let secondReceived: [Qonversion.DeferredPurchase] = await second.received
        XCTAssertEqual(firstReceived.map(\.transaction.id), ["once-1"])
        XCTAssertTrue(secondReceived.isEmpty, "a purchase the host already received must not be repeated")
    }

    func testABufferedPurchaseGoesToTheFirstSubscriptionOnly() async {
        // The approval is processed before the host wires anything up: it
        // waits, and the subscription that takes it consumes it.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        manager.transactionUpdated(makeTransaction(id: "once-2"))
        await waitUntil { !self.facade.finishedTransactions.isEmpty }

        let first = StreamCollector(manager.deferredPurchases())
        await waitUntil { await !first.received.isEmpty }
        let second = StreamCollector(manager.deferredPurchases())
        try? await Task.sleep(nanoseconds: 200_000_000)

        let firstReceived: [Qonversion.DeferredPurchase] = await first.received
        let secondReceived: [Qonversion.DeferredPurchase] = await second.received
        XCTAssertEqual(firstReceived.map(\.transaction.id), ["once-2"])
        XCTAssertTrue(secondReceived.isEmpty, "the buffered purchase was already taken")
    }

    func testConcurrentSubscriptionsBothReceiveTheSamePurchase() async {
        // Broadcast, not hand-off: everybody listening at the moment of the
        // approval hears it.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let first = StreamCollector(manager.deferredPurchases())
        let second = StreamCollector(manager.deferredPurchases())
        try? await Task.sleep(nanoseconds: 100_000_000)

        manager.transactionUpdated(makeTransaction(id: "both-1"))

        await waitUntil {
            let firstEmpty: Bool = await first.received.isEmpty
            let secondEmpty: Bool = await second.received.isEmpty
            return !firstEmpty && !secondEmpty
        }
        let firstReceived: [Qonversion.DeferredPurchase] = await first.received
        let secondReceived: [Qonversion.DeferredPurchase] = await second.received
        XCTAssertEqual(firstReceived.map(\.transaction.id), ["both-1"])
        XCTAssertEqual(secondReceived.map(\.transaction.id), ["both-1"])
    }

    func testAPurchaseNobodyReceivedComesBackOnTheNextLaunch() async {
        // Ask to Buy approved with the app in the background and no
        // subscription alive. The event must not be written off as delivered.
        manager = makeManager(launchMode: .analytics)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        manager.transactionUpdated(makeTransaction(id: "unheard-1"))
        await waitUntil { self.service.sentTransactions.count >= 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)

        // "Next launch": a fresh manager over the same storage, re-delivered
        // by the store because Analytics mode never finishes anything.
        let relaunched: PurchasesManager = makeManager(launchMode: .analytics)
        let collector = StreamCollector(relaunched.deferredPurchases())
        relaunched.transactionUpdated(makeTransaction(id: "unheard-1"))

        await waitUntil { await !collector.received.isEmpty }
        let received: [Qonversion.DeferredPurchase] = await collector.received
        XCTAssertEqual(received.map(\.transaction.id), ["unheard-1"], "a purchase nobody heard must not be lost")
    }

    func testUserChangeClearsTheEntitlementsBacklogSoTheNewUserGetsNoStaleSnapshot() async {
        // A snapshot buffered for the previous user describes access that
        // belongs to nobody after the uid moves: a new subscriber must not
        // read it as its own.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        manager.transactionUpdated(makeTransaction(id: "before-switch"))
        await waitUntil { !self.facade.finishedTransactions.isEmpty }

        manager.userDidChange()

        let collector = StreamCollector(manager.entitlementsUpdates())
        try? await Task.sleep(nanoseconds: 200_000_000)
        let received: [[String: Qonversion.Entitlement]] = await collector.received
        XCTAssertTrue(received.isEmpty, "the previous user's snapshot must not reach the new user's subscriber")
    }

    func testUserChangeClearsTheDeferredPurchasesBacklogAndUnclaimsItsTransactionForRedelivery() async {
        // Nobody heard the approval before the switch. It must not be simply
        // dropped: the transaction is unclaimed so the funnel can emit it
        // again, recalculated for whoever is the user now — a subscriber that
        // arrives after the switch must not be handed the stale pre-switch
        // backlog entry instead.
        manager = makeManager(launchMode: .analytics)
        entitlementsManager.entitlementsResult = ["previous_user_entitlement": entitlement(id: "previous_user_entitlement")]

        manager.transactionUpdated(makeTransaction(id: "switch-1"))
        await waitUntil { self.service.sentTransactions.count >= 1 }

        manager.userDidChange()
        entitlementsManager.entitlementsResult = ["new_user_entitlement": entitlement(id: "new_user_entitlement")]

        let collector = StreamCollector(manager.deferredPurchases())
        await waitUntil { self.manager.deferredPurchasesMulticast.subscriberCount >= 1 }
        manager.transactionUpdated(makeTransaction(id: "switch-1"))

        await waitUntil { await !collector.received.isEmpty }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let received: [Qonversion.DeferredPurchase] = await collector.received
        XCTAssertEqual(received.count, 1, "the transaction must be surfaced exactly once, not lost and not doubled")
        XCTAssertEqual(received.first?.transaction.id, "switch-1")
        XCTAssertEqual(received.first?.entitlements.keys.sorted(), ["new_user_entitlement"],
                       "the redelivery must carry the NEW user's entitlements, not a replay of the stale pre-switch snapshot")
    }

    func testAPromoIntentHandedToASubscriptionIsNotRepeatedToTheNextOne() async {
        // Acting on the same intent twice would run the purchase flow twice.
        manager.emitPromoPurchaseIntent(storeProductId: "com.app.promo")

        let first = StreamCollector(manager.promoPurchaseIntents())
        await waitUntil { await !first.received.isEmpty }
        let second = StreamCollector(manager.promoPurchaseIntents())
        try? await Task.sleep(nanoseconds: 200_000_000)

        let secondReceived: [Qonversion.PromoPurchaseIntent] = await second.received
        XCTAssertTrue(secondReceived.isEmpty, "the intent was already handed over")
    }

    func testTheDeferredPurchasesBufferHasNoExpiryDeadline() {
        // The replay window used to drop an approval the host had not
        // subscribed for yet; a deadline cannot be caught by waiting it out,
        // so the wiring itself is the assertion.
        XCTAssertEqual(manager.deferredPurchasesMulticast.backlog, .deliveredOnce)
        XCTAssertFalse(manager.deferredPurchasesMulticast.backlogLifetime.isFinite,
                       "an approval nobody received waits for the host, not for a deadline")
    }

    func testThePromoPurchaseIntentsBufferHasNoExpiryDeadline() {
        // A promo intent processed with the paywall not built yet must wait
        // for it, however long that takes — 300 seconds contradicted the
        // documented "no deadline" contract.
        XCTAssertEqual(manager.promoIntentsMulticast.backlog, .deliveredOnce)
        XCTAssertFalse(manager.promoIntentsMulticast.backlogLifetime.isFinite,
                       "a promo intent nobody received waits for the host, not for a deadline")
    }

    func testEntitlementsUpdatesStillReachesEveryLaterSubscription() async {
        // Unchanged on purpose: an entitlements snapshot is idempotent state,
        // so a host that re-subscribes must still be able to read the latest.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        manager.transactionUpdated(makeTransaction(id: "snapshot-1"))
        await waitUntil { !self.facade.finishedTransactions.isEmpty }

        let first = StreamCollector(manager.entitlementsUpdates())
        await waitUntil { await !first.received.isEmpty }
        let second = StreamCollector(manager.entitlementsUpdates())

        await waitUntil { await !second.received.isEmpty }
        let secondReceived: [[String: Qonversion.Entitlement]] = await second.received
        XCTAssertEqual(secondReceived.first?.keys.sorted(), ["premium"], "the snapshot stays readable by later subscriptions")
    }

    // MARK: - promotional offer signature

    func testPromotionalOfferPassesGateAndForwardsToService() async throws {
        facade.historicalDataResult = [makeTransaction(id: "history-1")]
        service.promotionalOfferResult = Qonversion.PromotionalOffer(offerId: "offer1", keyId: "KEY", nonce: UUID(), signature: Data([0x01]), timestamp: 1)

        let offer = try await manager.promotionalOffer(for: makeProduct(storeId: "com.app.pro"), discountId: "offer1")

        XCTAssertEqual(userManager.obtainUserCallsCount, 1, "the signature request must pass the current-user gate")
        XCTAssertEqual(service.promotionalOfferCalls.first?.userId, uid)
        XCTAssertEqual(service.promotionalOfferCalls.first?.offerId, "offer1")
        XCTAssertEqual(service.promotionalOfferCalls.first?.productStoreId, "com.app.pro")
        XCTAssertEqual(offer.offerId, "offer1")
    }

    func testPromotionalOfferDoesNotSyncThePurchaseHistory() async throws {
        facade.historicalDataResult = [makeTransaction(id: "history-1")]
        service.promotionalOfferResult = Qonversion.PromotionalOffer(offerId: "offer1", keyId: "KEY", nonce: UUID(), signature: Data(), timestamp: 1)

        _ = try await manager.promotionalOffer(for: makeProduct(), discountId: "offer1")

        XCTAssertEqual(facade.historicalDataCallsCount, 0, "signing must not upload the store history")
        XCTAssertTrue(service.sentTransactions.isEmpty)
    }

    func testPromotionalOfferIsSignedWhenTheStoreHistoryIsUnavailable() async throws {
        facade.historicalDataError = MockError.stubbed
        service.promotionalOfferResult = Qonversion.PromotionalOffer(offerId: "offer1", keyId: "KEY", nonce: UUID(), signature: Data(), timestamp: 1)

        let offer = try await manager.promotionalOffer(for: makeProduct(), discountId: "offer1")

        XCTAssertEqual(offer.offerId, "offer1", "an unreadable store history must not deny the signature")
        XCTAssertEqual(service.promotionalOfferCalls.count, 1)
    }

    func testPromotionalOfferKeepsTheCurrentUser() async throws {
        facade.historicalDataResult = [makeTransaction(id: "history-1")]
        service.reportedOwnerUserId = "QON_owner"
        service.promotionalOfferResult = Qonversion.PromotionalOffer(offerId: "offer1", keyId: "KEY", nonce: UUID(), signature: Data(), timestamp: 1)

        _ = try await manager.promotionalOffer(for: makeProduct(), discountId: "offer1")

        XCTAssertTrue(userManager.switchedToUserIds.isEmpty, "signing must not switch the Qonversion user")
        XCTAssertEqual(service.promotionalOfferCalls.first?.userId, uid)
    }

    // MARK: - promoted purchases (App Store promo intents)

    func testPromoIntentIsEmittedToTheStream() async {
        let collector = StreamCollector(manager.promoPurchaseIntents())

        manager.emitPromoPurchaseIntent(storeProductId: "com.app.promo")

        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        XCTAssertEqual(received.map(\.productId), ["com.app.promo"])
        XCTAssertTrue(facade.purchasedStoreIds.isEmpty, "nothing is purchased until the host asks")
    }

    func testIntentPurchaseRunsTheFullPurchaseFlow() async throws {
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "t1", productId: "com.app.promo")
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let collector = StreamCollector(manager.promoPurchaseIntents())
        manager.emitPromoPurchaseIntent(storeProductId: "com.app.promo")
        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        let intent = try XCTUnwrap(received.first)

        let result = try await intent.purchase()

        XCTAssertEqual(facade.purchasedStoreIds, ["com.app.promo"])
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1"])
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["t1"])
        XCTAssertEqual(result.entitlements.keys.sorted(), ["premium"])
    }

    func testIntentPurchaseIsOneShot() async throws {
        facade.purchaseResult = makeTransaction(id: "t1", productId: "com.app.promo")
        let collector = StreamCollector(manager.promoPurchaseIntents())
        manager.emitPromoPurchaseIntent(storeProductId: "com.app.promo")
        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        let intent = try XCTUnwrap(received.first)
        _ = try await intent.purchase()

        do {
            _ = try await intent.purchase()
            XCTFail("Expected the second purchase() call to throw")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .promoPurchaseIntentAlreadyHandled)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(facade.purchasedStoreIds, ["com.app.promo"], "the flow must run exactly once")
    }

    func testIntentEmittedBeforeAnySubscriberIsDeliveredToTheFirstOne() async {
        // The intent can arrive at app start before the host subscribes —
        // it must not be lost.
        manager.emitPromoPurchaseIntent(storeProductId: "com.app.promo")

        let collector = StreamCollector(manager.promoPurchaseIntents())

        await waitUntil { await !collector.received.isEmpty }
        let received = await collector.received
        XCTAssertEqual(received.map(\.productId), ["com.app.promo"])
    }

    // MARK: - handlePurchases (analytics ingestion)

    func testHandleTransactionsReportsEachThroughGateAndNeverFinishes() async {
        await manager.handle(transactions: [makeTransaction(id: "t1"), makeTransaction(id: "t2", productId: "com.app.lite")])

        XCTAssertEqual(userManager.obtainUserCallsCount, 1, "the user gate must be passed before reporting")
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1", "t2"])
        XCTAssertTrue(facade.finishedTransactions.isEmpty, "the host app owns the transaction lifecycle")
    }

    func testHandleTransactionsIsDeduplicatedAgainstItselfAndTheListener() async {
        let transaction = makeTransaction(id: "t1")

        await manager.handle(transactions: [transaction])
        await manager.handle(transactions: [transaction])
        manager.transactionUpdated(transaction)

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1"])
    }

    func testHandleTransactionsReportFailureIsSwallowedAndRetriable() async {
        service.error = MockError.stubbed

        await manager.handle(transactions: [makeTransaction(id: "t1")])

        XCTAssertTrue(facade.finishedTransactions.isEmpty)

        service.error = nil
        await manager.handle(transactions: [makeTransaction(id: "t1")])

        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1", "t1"], "a failed report must not poison the dedup")
    }

    func testHandleTransactionsWithEmptyInputDoesNothing() async {
        await manager.handle(transactions: [])

        XCTAssertEqual(userManager.obtainUserCallsCount, 0)
        XCTAssertTrue(service.sentTransactions.isEmpty)
    }

    func testHandleTransactionsUserGateFailureSkipsReporting() async {
        userManager.error = MockError.stubbed

        await manager.handle(transactions: [makeTransaction(id: "t1")])

        XCTAssertTrue(service.sentTransactions.isEmpty)
    }

    // MARK: - restore user switching

    func testRestoreSwitchesToTheTransactionsOwner() async throws {
        // The backend resolves the reported transaction to ANOTHER user.
        facade.restoreResult = [makeTransaction(id: "t1")]
        service.reportedOwnerUserId = "QON_owner"
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]

        _ = try await manager.restore()

        XCTAssertEqual(userManager.switchedToUserIds, ["QON_owner"])
    }

    func testRestoreDoesNotSwitchWhenTheOwnerMatches() async throws {
        facade.restoreResult = [makeTransaction(id: "t1")]
        service.reportedOwnerUserId = uid
        entitlementsManager.entitlementsResult = [:]

        _ = try await manager.restore()

        XCTAssertTrue(userManager.switchedToUserIds.isEmpty)
    }

    func testSyncHistoricalDataSwitchesToTheTransactionsOwner() async {
        facade.historicalDataResult = [makeTransaction(id: "t1")]
        service.reportedOwnerUserId = "QON_owner"

        await manager.syncHistoricalData()

        XCTAssertEqual(userManager.switchedToUserIds, ["QON_owner"])
    }

    // MARK: - backend entitlements survive a store failure on restore

    func testRestoreReturnsBackendEntitlementsWhenTheStoreFails() async throws {
        // A Stripe-only user on iOS: the store sync fails (no Apple receipt /
        // cancelled sign-in), but the backend knows the entitlements.
        facade.restoreError = QonversionError(type: .purchaseFailed)
        entitlementsManager.entitlementsResult = ["stripe_premium": entitlement(id: "stripe_premium")]

        let entitlements = try await manager.restore()

        XCTAssertEqual(entitlements.keys.sorted(), ["stripe_premium"])
        XCTAssertTrue(service.sentTransactions.isEmpty)
    }

    func testRestoreRethrowsTheStoreErrorWhenTheBackendHasNothing() async {
        facade.restoreError = QonversionError(type: .purchaseFailed)
        entitlementsManager.entitlementsResult = [:]

        do {
            _ = try await manager.restore()
            XCTFail("Expected the store error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRestoreNamesARawStoreCancellationWhenTheBackendHasNothing() async {
        // The public API documents QonversionError: a raw StoreKitError
        // escaping restore() cannot be classified by the host at all.
        facade.restoreError = StoreKitError.userCancelled
        entitlementsManager.entitlementsResult = [:]

        do {
            _ = try await manager.restore()
            XCTFail("Expected the store error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseCancelled)
        } catch {
            XCTFail("Raw store errors must never reach the integrator: \(error)")
        }
    }

    func testRestoreNamesARawTransportFailureWhenTheBackendHasNothing() async {
        facade.restoreError = URLError(.notConnectedToInternet)
        entitlementsManager.entitlementsResult = [:]

        do {
            _ = try await manager.restore()
            XCTFail("Expected the store error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .restoreFailed)
            XCTAssertNotNil(error.error as? URLError, "the underlying store error must stay reachable")
        } catch {
            XCTFail("Raw store errors must never reach the integrator: \(error)")
        }
    }

    // MARK: - historical data sync

    func testSyncHistoricalDataReportsLatestTransactionPerProductWithoutFinishing() async {
        let older = makeTransaction(id: "old", purchaseDate: Date(timeIntervalSince1970: 1_600_000_000))
        let newer = makeTransaction(id: "new", purchaseDate: Date(timeIntervalSince1970: 1_700_000_000))
        facade.historicalDataResult = [older, newer]

        await manager.syncHistoricalData()

        XCTAssertEqual(userManager.obtainUserCallsCount, 1, "the user gate must be passed first")
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["new"], "only the latest transaction per product is reported")
        XCTAssertTrue(facade.finishedTransactions.isEmpty, "historical transactions are never finished")
    }

    func testSyncHistoricalDataRunsOncePerInstall() async {
        facade.historicalDataResult = [makeTransaction(id: "t1")]

        await manager.syncHistoricalData()
        await manager.syncHistoricalData()

        XCTAssertEqual(service.sentTransactions.count, 1)

        // The flag is persisted: a fresh manager over the same storage skips too.
        let relaunched = makeManager()
        await relaunched.syncHistoricalData()
        XCTAssertEqual(service.sentTransactions.count, 1)
    }

    func testConcurrentHistoricalSyncCallsShareOneStoreHistoryRead() async {
        let gate = PurchasesAsyncGate()
        facade.historicalDataResult = [makeTransaction(id: "t1")]
        facade.onHistoricalData = { await gate.wait() }

        let first = Task { await self.manager.syncHistoricalData() }
        await waitUntil { self.facade.historicalDataCallsCount == 1 }
        let second = Task { await self.manager.syncHistoricalData() }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(facade.historicalDataCallsCount, 1, "concurrent callers must join the same sync")
        await gate.open()
        _ = await (first.value, second.value)
        XCTAssertEqual(facade.historicalDataCallsCount, 1)
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1"])
    }

    func testSyncHistoricalDataFailureIsRetriableOnNextCall() async {
        facade.historicalDataResult = [makeTransaction(id: "t1")]
        service.error = MockError.stubbed

        await manager.syncHistoricalData()

        service.error = nil
        await manager.syncHistoricalData()

        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1", "t1"], "a failed sync must not latch the once-per-install flag")
    }

    func testAHistoricalSyncThatOutlivesAUserSwitchDoesNotFlagTheNewUsersInstallAsSynced() async {
        // The reports are still in flight for the departing user when the uid
        // moves; the install-global "synced" flag and the owner switch belong
        // to the session that started the run, not to whoever is current when
        // it finishes.
        facade.historicalDataResult = [makeTransaction(id: "t1")]
        let gate = PurchasesAsyncGate()
        service.onSend = { await gate.wait() }

        let sync = Task { await self.manager.syncHistoricalData() }
        await waitUntil { self.service.sentTransactions.count >= 1 }

        manager.userDidChange()
        config.userId = "QON_other"
        await gate.open()
        let synced = await sync.value

        XCTAssertFalse(synced, "a sync racing a user switch must not report success")
        XCTAssertFalse(localStorage.bool(forKey: "qonversion.keys.historicalDataSynced"),
                       "the flag must not be set for a run that raced a user switch")
    }

    func testSyncHistoricalDataStartsAFreshRunAfterAUserSwitchInvalidatedTheInFlightOne() async {
        facade.historicalDataResult = [makeTransaction(id: "t1")]
        let gate = PurchasesAsyncGate()
        service.onSend = { await gate.wait() }
        let staleRun = Task { await self.manager.syncHistoricalData() }
        await waitUntil { self.service.sentTransactions.count >= 1 }

        manager.userDidChange()
        config.userId = "QON_other"
        let freshRun = Task { await self.manager.syncHistoricalData() }
        await waitUntil { self.facade.historicalDataCallsCount >= 2 }

        XCTAssertEqual(facade.historicalDataCallsCount, 2,
                       "a call made after the switch must start its own store fetch, not join the stale run")

        await gate.open()
        _ = await (staleRun.value, freshRun.value)
    }

    func testSyncHistoricalDataSharesTheDedupGateWithTheListener() async {
        let transaction = makeTransaction(id: "t1")
        manager.transactionUpdated(transaction)
        await waitUntil { self.service.sentTransactions.count >= 1 }

        facade.historicalDataResult = [transaction]
        await manager.syncHistoricalData()

        XCTAssertEqual(service.sentTransactions.count, 1, "an already-reported transaction must not be re-sent")
    }

    // MARK: - persisted purchase associations (contextKeys / screenUid)

    func testSweepAttachesPersistedAssociationsOfTheOriginalPurchase() async {
        // The purchase was made through the SDK with associations, the report
        // failed, the app restarted: the sweep must re-report WITH them.
        manager = makeManager(launchMode: .subscriptionManagement)
        facade.purchaseResult = makeTransaction(id: "t1")
        service.error = QonversionError(type: .internal)
        _ = try? await manager.purchase(makeProduct(), options: Qonversion.PurchaseOptions(contextKeys: ["main"], screenUid: "scr_1"))

        // "Next launch": a fresh manager over the same storage.
        service.error = nil
        let relaunched = makeManager(launchMode: .subscriptionManagement)
        facade.unfinishedTransactionsResult = [makeTransaction(id: "t1")]
        await relaunched.processUnfinishedTransactions()

        let reported = service.sentTransactions.last
        XCTAssertEqual(reported?.transaction.id, "t1")
        XCTAssertEqual(reported?.options?.contextKeys, ["main"])
        XCTAssertEqual(reported?.options?.screenUid, "scr_1")
    }

    func testSuccessfulPurchaseReportClearsPersistedAssociations() async throws {
        facade.purchaseResult = makeTransaction(id: "t1")
        _ = try await manager.purchase(makeProduct(), options: Qonversion.PurchaseOptions(contextKeys: ["main"]))

        // A later out-of-band report of the same product must not inherit them.
        manager.transactionUpdated(makeTransaction(id: "t2"))
        await waitUntil { self.service.sentTransactions.count >= 2 }

        XCTAssertNil(service.sentTransactions.last?.options ?? nil)
    }

    func testFailedStorePurchaseClearsPersistedAssociations() async {
        facade.purchaseError = QonversionError(type: .purchaseCancelled)
        _ = try? await manager.purchase(makeProduct(), options: Qonversion.PurchaseOptions(contextKeys: ["main"]))

        // The next unrelated transaction of this product must not pick up
        // associations of a purchase that never happened.
        facade.unfinishedTransactionsResult = [makeTransaction(id: "t1")]
        let subMgmt = makeManager(launchMode: .subscriptionManagement)
        await subMgmt.processUnfinishedTransactions()

        XCTAssertNil(service.sentTransactions.last?.options ?? nil)
    }

    func testObservedUpdateAttachesPersistedAssociations() async {
        // Ask to Buy: the purchase started through the SDK, the approved
        // transaction arrives via the listener later.
        facade.purchaseError = QonversionError(type: .purchasePending)
        _ = try? await manager.purchase(makeProduct(), options: Qonversion.PurchaseOptions(contextKeys: ["main"], screenUid: "scr_1"))

        manager.transactionUpdated(makeTransaction(id: "t1"))
        await waitUntil { self.service.sentTransactions.count >= 1 }

        XCTAssertEqual(service.sentTransactions.last?.options?.contextKeys, ["main"])
        XCTAssertEqual(service.sentTransactions.last?.options?.screenUid, "scr_1")
    }

    // MARK: - unfinished transactions sweep at launch

    func testUnfinishedSweepInAnalyticsModeReportsButNeverFinishes() async {
        // Production parity: a purchase whose report failed offline must not
        // be lost in Analytics mode either — it is re-reported, but the host
        // app still owns the transaction lifecycle.
        manager = makeManager(launchMode: .analytics)
        facade.unfinishedTransactionsResult = [makeTransaction(id: "t1")]

        await manager.processUnfinishedTransactions()

        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["t1"])
        XCTAssertTrue(facade.finishedTransactions.isEmpty, "the host app owns the transaction lifecycle in Analytics mode")
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

    func testObservedUpdateForPurchasedTransactionIsNotReportedAgain() async throws {
        let transaction = makeTransaction(id: "t1")
        facade.purchaseResult = transaction

        _ = try await manager.purchase(makeProduct())
        // The same transaction surfaces through Transaction.updates.
        manager.transactionUpdated(transaction)

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(service.sentTransactions.count, 1, "a reported purchase must not be re-reported by the listener")
    }

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

    // MARK: - the host hears the transaction whichever path claims it

    func testTheLaunchSweepSurfacesTheTransactionToTheHost() async {
        // The sweep and the listener race for the same transaction at launch.
        // Whichever wins, the host must hear the purchase — the sweep also
        // FINISHES it in subscription management mode, so a transaction it
        // claimed silently would never come back through the listener.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        facade.unfinishedTransactionsResult = [makeTransaction(id: "swept-1")]
        let collector = StreamCollector(manager.deferredPurchases())

        await manager.processUnfinishedTransactions()

        await waitUntil { await !collector.received.isEmpty }
        let received: [Qonversion.DeferredPurchase] = await collector.received
        XCTAssertEqual(received.map(\.transaction.id), ["swept-1"])
        XCTAssertEqual(received.first?.entitlements.keys.sorted(), ["premium"])
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["swept-1"])
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["swept-1"])
    }

    func testTheSweepFinishesAndSurfacesATransactionTheReplayAlreadyReported() async {
        // The offline replay POSTs a queued report but cannot finish a StoreKit
        // transaction or emit a deferred purchase — the sweep completes the
        // outcome without posting the purchase a second time.
        let reportsGate = TransactionReportsGate()
        reportsGate.markReported("replayed-1")
        manager = makeManager(launchMode: .subscriptionManagement, reportsGate: reportsGate)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        facade.unfinishedTransactionsResult = [makeTransaction(id: "replayed-1")]
        let collector = StreamCollector(manager.deferredPurchases())

        await manager.processUnfinishedTransactions()

        await waitUntil { await !collector.received.isEmpty }
        XCTAssertTrue(service.sentTransactions.isEmpty, "the replay already delivered this report")
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["replayed-1"])
        let received: [Qonversion.DeferredPurchase] = await collector.received
        XCTAssertEqual(received.map(\.transaction.id), ["replayed-1"])
    }

    func testATransactionSurfacedByTheSweepIsNotEmittedAgainOnTheNextLaunch() async {
        // Analytics mode never finishes anything, so the store re-delivers the
        // same transaction on every cold start.
        manager = makeManager(launchMode: .analytics)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        facade.unfinishedTransactionsResult = [makeTransaction(id: "swept-2")]
        let collector = StreamCollector(manager.deferredPurchases())

        await manager.processUnfinishedTransactions()
        await waitUntil { await !collector.received.isEmpty }

        // "Next launch": a fresh manager over the same storage, so only the
        // persisted surfaced-transactions set can stop the second emission.
        let relaunched: PurchasesManager = makeManager(launchMode: .analytics)
        let relaunchedCollector = StreamCollector(relaunched.deferredPurchases())
        relaunched.transactionUpdated(makeTransaction(id: "swept-2"))
        await waitUntil { self.service.sentTransactions.count >= 2 }

        // A transaction the listener DOES surface, delivered afterwards: its
        // emission is the marker that the previous one produced none.
        relaunched.transactionUpdated(makeTransaction(id: "fresh-2", productId: "com.app.lite"))
        await waitUntil { await !relaunchedCollector.received.isEmpty }

        let receivedAfterRelaunch: [Qonversion.DeferredPurchase] = await relaunchedCollector.received
        XCTAssertEqual(receivedAfterRelaunch.map(\.transaction.id), ["fresh-2"],
                       "a purchase the sweep already surfaced must not come back on the next launch")
    }

    func testTheListenerWinningTheGateKeepsTheSweepFromRepeatingTheOutcome() async {
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let transaction: Qonversion.Transaction = makeTransaction(id: "race-1")
        facade.unfinishedTransactionsResult = [transaction]
        let collector = StreamCollector(manager.deferredPurchases())

        manager.transactionUpdated(transaction)
        await waitUntil { self.service.sentTransactions.count >= 1 }

        await manager.processUnfinishedTransactions()
        await waitUntil { await !collector.received.isEmpty }

        let received: [Qonversion.DeferredPurchase] = await collector.received
        XCTAssertEqual(received.map(\.transaction.id), ["race-1"])
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["race-1"])
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["race-1"])
    }

    func testTheSweepAndTheListenerRacingOneTransactionProduceOneOutcome() async {
        // The sweep is already inside its report when the listener picks the
        // same transaction up: exactly one report, one finish, one emission.
        manager = makeManager(launchMode: .subscriptionManagement)
        entitlementsManager.entitlementsResult = ["premium": entitlement(id: "premium")]
        let transaction: Qonversion.Transaction = makeTransaction(id: "race-2")
        facade.unfinishedTransactionsResult = [transaction]
        let collector = StreamCollector(manager.deferredPurchases())
        let sweepIsReporting = PurchasesAsyncGate()
        let listenerHasArrived = PurchasesAsyncGate()
        service.onSend = {
            await sweepIsReporting.open()
            await listenerHasArrived.wait()
        }

        let sweep = Task { await self.manager.processUnfinishedTransactions() }
        await sweepIsReporting.wait()
        manager.transactionUpdated(transaction)
        await listenerHasArrived.open()
        await sweep.value

        await waitUntil { await !collector.received.isEmpty }
        // The listener may still be running: a transaction it does surface,
        // delivered now, marks the point where its earlier task is done.
        service.onSend = nil
        manager.transactionUpdated(makeTransaction(id: "marker-2", productId: "com.app.lite"))
        await waitUntil { await collector.received.count >= 2 }

        let received: [Qonversion.DeferredPurchase] = await collector.received
        XCTAssertEqual(received.map(\.transaction.id), ["race-2", "marker-2"])
        XCTAssertEqual(service.sentTransactions.map(\.transaction.id), ["race-2", "marker-2"])
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["race-2", "marker-2"])
    }
}

/// Collects everything a stream emits.
private actor StreamCollector<Element> {

    private(set) var received: [Element] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<Element>) {
        Task { await start(stream) }
    }

    private func start(_ stream: AsyncStream<Element>) {
        task = Task {
            for await element in stream {
                append(element)
            }
        }
    }

    private func append(_ element: Element) {
        received.append(element)
    }
}

/// A reusable async gate: wait() suspends until open() is called.
private actor PurchasesGateStorage {
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

private final class PurchasesAsyncGate: @unchecked Sendable {
    private let storage = PurchasesGateStorage()
    func open() async { await storage.open() }
    func wait() async { await storage.wait() }
}
