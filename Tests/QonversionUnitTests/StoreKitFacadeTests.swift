//
//  StoreKitFacadeTests.swift
//  QonversionUnitTests
//
//  Contract tests for the StoreKit facade (TDD — written before the implementation).
//
//  The facade speaks ONLY Qonversion.* domain types, so all its logic is
//  unit-testable through the domain-typed StoreKit 2 wrapper mock. The thin
//  Apple-type mapping inside the real wrappers is the only untested edge.
//

import XCTest
import StoreKit
@testable import Qonversion

final class StoreKitFacadeTests: XCTestCase {

    private var wrapper: MockStoreKit2Wrapper!
    private var facade: StoreKitFacade!
    private var observer: RecordingFacadeDelegate!

    override func setUp() {
        super.setUp()
        wrapper = MockStoreKit2Wrapper()
        facade = StoreKitFacade(storeKitWrapper: wrapper, storeKitMapper: StoreKitMapper())
        observer = RecordingFacadeDelegate()
        facade.delegate = observer
    }

    override func tearDown() {
        facade.stopObservingTransactionUpdates()
        observer = nil
        facade = nil
        wrapper = nil
        super.tearDown()
    }

    private func makeTransaction(id: String, jws: String? = nil) -> Qonversion.Transaction {
        Qonversion.Transaction(id: id, productId: "product_" + id, jws: jws)
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Restore / historical data mapping

    func testRestoreReturnsWrapperTransactions() async throws {
        wrapper.restoreResult = [makeTransaction(id: "1"), makeTransaction(id: "2")]

        let restored = try await facade.restore()

        XCTAssertEqual(wrapper.restoreCallsCount, 1)
        XCTAssertEqual(restored.map(\.id), ["1", "2"])
    }

    func testHistoricalDataReturnsAllWrapperTransactions() async throws {
        wrapper.fetchAllResult = [makeTransaction(id: "1"), makeTransaction(id: "2"), makeTransaction(id: "3")]

        let history = try await facade.historicalData()

        XCTAssertEqual(history.map(\.id), ["1", "2", "3"])
    }

    func testCurrentEntitlementsPassesWrapperTransactionsThrough() async {
        wrapper.currentEntitlementsResult = [makeTransaction(id: "ent1", jws: "jws1")]

        let entitlements = await facade.currentEntitlements()

        XCTAssertEqual(entitlements.map(\.id), ["ent1"])
        XCTAssertEqual(entitlements.first?.jws, "jws1")
    }

    func testUnfinishedTransactionsPassesWrapperTransactionsThrough() async {
        wrapper.fetchUnfinishedResult = [makeTransaction(id: "u1", jws: "jws1")]

        let unfinished = await facade.unfinishedTransactions()

        XCTAssertEqual(unfinished.map(\.id), ["u1"])
        XCTAssertEqual(unfinished.first?.jws, "jws1")
    }

    // MARK: - Finish routing

    func testFinishForwardsToWrapper() async {
        let transaction = makeTransaction(id: "1")

        await facade.finish(transaction)

        XCTAssertEqual(wrapper.finishedTransactions.map(\.id), ["1"])
    }

    // MARK: - Transaction updates listener

    func testStartObservingDeliversVerifiedUpdatesToDelegate() async {
        facade.startObservingTransactionUpdates()
        await waitUntil { self.wrapper.transactionUpdatesCallsCount >= 1 }

        wrapper.emitUpdate(makeTransaction(id: "u1", jws: "jws-u1"))
        wrapper.emitUpdate(makeTransaction(id: "u2"))

        await waitUntil { self.observer.updatedTransactions.count >= 2 }
        XCTAssertEqual(observer.updatedTransactions.map(\.id), ["u1", "u2"])
        XCTAssertEqual(observer.updatedTransactions.first?.jws, "jws-u1")
    }

    func testObservedUpdatesAreNeverFinishedAutomatically() async {
        // In Analytics mode the host app owns the transaction lifecycle:
        // the SDK must not finish observed transactions on its own.
        facade.startObservingTransactionUpdates()
        await waitUntil { self.wrapper.transactionUpdatesCallsCount >= 1 }

        wrapper.emitUpdate(makeTransaction(id: "u1"))

        await waitUntil { self.observer.updatedTransactions.count >= 1 }
        XCTAssertTrue(wrapper.finishedTransactions.isEmpty, "the listener must not auto-finish transactions")
    }

    func testStartObservingTwiceSubscribesOnce() async {
        facade.startObservingTransactionUpdates()
        facade.startObservingTransactionUpdates()

        await waitUntil { self.wrapper.transactionUpdatesCallsCount >= 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(wrapper.transactionUpdatesCallsCount, 1)
    }

    func testStopObservingStopsDelivery() async {
        facade.startObservingTransactionUpdates()
        await waitUntil { self.wrapper.transactionUpdatesCallsCount >= 1 }

        facade.stopObservingTransactionUpdates()
        try? await Task.sleep(nanoseconds: 50_000_000)
        wrapper.emitUpdate(makeTransaction(id: "late"))
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(observer.updatedTransactions.isEmpty)
    }

    // MARK: - Purchase

    func testPurchaseThrowsWhenStoreProductCannotBeLoaded() async {
        // The wrapper returns no products for the requested id.
        do {
            _ = try await facade.purchase(storeId: "unknown.product")
            XCTFail("Expected purchase to throw when the store product cannot be loaded")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .storeProductsLoadingFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Continuation safety (SK1 products path)

    func testProductsAwaiterGetsErrorWhenFacadeDiesBeforeCompletion() async {
        // The completion is retained by the old wrapper (which the real
        // SKPaymentQueue keeps alive forever), so it CAN fire after the facade
        // is gone — e.g. after a repeated initialize() rebuilt the managers.
        // The awaiting task must receive an error, not hang forever.
        let oldWrapper = MockStoreKitOldWrapper()
        var dyingFacade: StoreKitFacade? = StoreKitFacade(storeKitOldWrapper: oldWrapper, storeKitMapper: StoreKitMapper())

        let awaiter = Task { () -> Error? in
            do {
                _ = try await dyingFacade?.skOneProducts(for: ["p1"])
                return nil
            } catch {
                return error
            }
        }

        await waitUntil { oldWrapper.productsCompletions.count >= 1 }
        dyingFacade = nil
        oldWrapper.productsCompletions.first?(nil, MockError.stubbed)

        let result = await withTimeout(seconds: 2) { await awaiter.value }

        XCTAssertNotNil(result ?? nil, "the awaiting task must be resumed with an error, not suspended forever")
    }

    private func withTimeout<T>(seconds: TimeInterval, _ operation: @escaping () async -> T) async -> T? {
        return await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Purchase outcome mapping (pure)

    func testPurchaseOutcomeMapsToGranularErrors() {
        XCTAssertNil(StoreKitPurchaseOutcome.success(makeTransaction(id: "1")).qonversionError())
        XCTAssertEqual(StoreKitPurchaseOutcome.userCancelled.qonversionError()?.type, .purchaseCancelled)
        XCTAssertEqual(StoreKitPurchaseOutcome.pending.qonversionError()?.type, .purchasePending)
        XCTAssertEqual(StoreKitPurchaseOutcome.unverified(MockError.stubbed).qonversionError()?.type, .transactionVerificationFailed)
        XCTAssertEqual(StoreKitPurchaseOutcome.failed(nil).qonversionError()?.type, .purchaseFailed)
    }

    // MARK: - jws proof

    func testTransactionCarriesJwsProof() {
        let transaction = makeTransaction(id: "1", jws: "signed-payload")

        XCTAssertEqual(transaction.jws, "signed-payload")
    }
}

// MARK: - Helpers

private final class RecordingFacadeDelegate: StoreKitFacadeDelegate {

    private(set) var updatedTransactions: [Qonversion.Transaction] = []

    @available(iOS 16.4, macOS 14.4, *)
    func promoPurchaseIntent(product: Product) { }

    func transactionUpdated(_ transaction: Qonversion.Transaction) {
        updatedTransactions.append(transaction)
    }
}

// MARK: - StoreKit 1 purchase path

/// SKProduct/SKPaymentTransaction stand-ins: the real initializers produce
/// empty objects, so the readonly fields are overridden.
private final class FakeSKProduct: SKProduct {
    private let id: String
    init(id: String) { self.id = id; super.init() }
    override var productIdentifier: String { id }
    // The empty SKProduct backs these with nil and crashes on access.
    override var price: NSDecimalNumber { NSDecimalNumber(string: "9.99") }
    override var priceLocale: Locale { Locale(identifier: "en_US") }
}

private final class FakeSKTransaction: SKPaymentTransaction {
    private let fakePayment: SKPayment
    private let state: SKPaymentTransactionState
    private let fakeError: Error?

    init(productId: String, state: SKPaymentTransactionState, error: Error? = nil) {
        self.fakePayment = SKPayment(product: FakeSKProduct(id: productId))
        self.state = state
        self.fakeError = error
        super.init()
    }

    override var payment: SKPayment { fakePayment }
    override var transactionState: SKPaymentTransactionState { state }
    override var error: Error? { fakeError }
    override var transactionIdentifier: String? { "sk1-transaction" }
}

final class StoreKitOldPurchaseTests: XCTestCase {

    private var oldWrapper: MockStoreKitOldWrapper!
    private var facade: StoreKitFacade!

    override func setUp() {
        super.setUp()
        oldWrapper = MockStoreKitOldWrapper()
        facade = StoreKitFacade(storeKitOldWrapper: oldWrapper, storeKitMapper: StoreKitMapper())
        facade.loadedOldProducts = ["com.app.pro": FakeSKProduct(id: "com.app.pro")]
    }

    override func tearDown() {
        facade = nil
        oldWrapper = nil
        super.tearDown()
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testSuccessfulPurchaseMapsThePurchasedTransaction() async throws {
        async let purchased = facade.skOnePurchase(storeId: "com.app.pro")
        await waitUntil { self.oldWrapper.purchaseCompletions.count >= 1 }

        oldWrapper.purchaseCompletions.first?([FakeSKTransaction(productId: "com.app.pro", state: .purchased)], nil)

        let transaction = try await purchased
        XCTAssertEqual(transaction.productId, "com.app.pro")
        XCTAssertEqual(transaction.id, "sk1-transaction")
        XCTAssertNotNil(transaction.skPaymentTransaction, "finish must be able to route back to StoreKit 1")
    }

    func testCancelledPurchaseThrowsPurchaseCancelled() async {
        async let purchased = facade.skOnePurchase(storeId: "com.app.pro")
        await waitUntil { self.oldWrapper.purchaseCompletions.count >= 1 }

        let cancelled = FakeSKTransaction(productId: "com.app.pro", state: .failed, error: SKError(.paymentCancelled))
        oldWrapper.purchaseCompletions.first?([cancelled], nil)

        do {
            _ = try await purchased
            XCTFail("Expected purchaseCancelled")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseCancelled)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testDeferredPurchaseThrowsPurchasePending() async {
        async let purchased = facade.skOnePurchase(storeId: "com.app.pro")
        await waitUntil { self.oldWrapper.purchaseCompletions.count >= 1 }

        oldWrapper.purchaseCompletions.first?([FakeSKTransaction(productId: "com.app.pro", state: .deferred)], nil)

        do {
            _ = try await purchased
            XCTFail("Expected purchasePending")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchasePending)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFailedPurchaseWithoutCancellationThrowsPurchaseFailed() async {
        async let purchased = facade.skOnePurchase(storeId: "com.app.pro")
        await waitUntil { self.oldWrapper.purchaseCompletions.count >= 1 }

        let failed = FakeSKTransaction(productId: "com.app.pro", state: .failed, error: SKError(.paymentInvalid))
        oldWrapper.purchaseCompletions.first?([failed], nil)

        do {
            _ = try await purchased
            XCTFail("Expected purchaseFailed")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testUnknownProductThrowsWithoutStorePurchase() async {
        // The product cannot be loaded: the wrapper products request never
        // resolves in this mock, so the purchase must fail fast.
        facade.loadedOldProducts = [:]

        async let purchased = facade.skOnePurchase(storeId: "unknown")
        await waitUntil { self.oldWrapper.productsCompletions.count >= 1 }
        oldWrapper.productsCompletions.first?(nil, MockError.stubbed)

        do {
            _ = try await purchased
            XCTFail("Expected storeProductsLoadingFailed")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .storeProductsLoadingFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(oldWrapper.purchasedProducts.isEmpty)
    }
}
