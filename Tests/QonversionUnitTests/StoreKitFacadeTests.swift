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

    // MARK: - storefront changes

    func testStorefrontChangeDropsTheLoadedProducts() async {
        // Prices, availability and offers are per-storefront: keeping the
        // previous storefront's products would show the wrong prices.
        facade.startObservingTransactionUpdates()
        await waitUntil { self.wrapper.transactionUpdatesCallsCount >= 1 }
        _ = try? await facade.products(for: ["com.app.pro"])

        wrapper.emitStorefrontChange()

        await waitUntil { self.facade.loadedProducts.isEmpty }
        XCTAssertTrue(facade.loadedProducts.isEmpty)
    }

    func testProductsLoadedForThePreviousStorefrontDoNotRepopulateTheClearedCache() async {
        // The paywall opens in the US store and the load hangs in the network;
        // the user switches to the JP store, the change empties the cache — and
        // the load then finishes and writes the US products back in.
        facade.startObservingTransactionUpdates()
        await waitUntil { self.wrapper.transactionUpdatesCallsCount >= 1 }
        let generationAtLoadStart: Int = facade.productsCacheGeneration

        wrapper.emitStorefrontChange()
        await waitUntil { self.facade.productsCacheGeneration != generationAtLoadStart }

        XCTAssertFalse(facade.storeLoadedProducts([], ifGenerationIs: generationAtLoadStart),
                       "a load started before the storefront change describes a store the user has left")
        XCTAssertTrue(facade.storeLoadedProducts([], ifGenerationIs: facade.productsCacheGeneration),
                      "a load started after it is the one that fills the cache")
    }

    // MARK: - unverified transactions

    func testAnUnverifiedTransactionIsDroppedVisibly() {
        // Local JWS verification fails for real reasons (a rolled system clock,
        // an App Store root certificate rotation). The transaction must not be
        // reported — an unverified proof proves nothing — but a silent drop
        // leaves a paid purchase unexplained forever.
        var messages: [String] = []
        var levels: [Qonversion.LogLevel] = []
        let logger = LoggerWrapper(sink: { level, message in
            levels.append(level)
            messages.append(message)
        })
        let loggingFacade = StoreKitFacade(storeKitWrapper: wrapper, storeKitMapper: StoreKitMapper(), logger: logger)

        loggingFacade.reportUnverifiedTransaction(MockError.stubbed, source: "handlePurchases")
        loggingFacade.reportUnverifiedTransaction(nil, source: "handlePurchases")

        XCTAssertEqual(loggingFacade.unverifiedTransactionsCount, 2)
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages.allSatisfy { $0.contains("handlePurchases") })
        XCTAssertEqual(levels, [.error, .error])
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

    func testPurchaseOfAProductTheStoreDoesNotKnowIsNamedAsSuch() async {
        // The wrapper returns no products for the requested id: nothing
        // failed to load — the store has no such product.
        do {
            _ = try await facade.purchase(storeId: "unknown.product")
            XCTFail("Expected purchase to throw when the store has no such product")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .storeProductNotAvailable)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPurchaseMapsAStoreFailureOfTheProductLoad() async {
        // Product.products(for:) throws raw StoreKit errors; a purchase must
        // answer with the SDK's own error whatever leg of it failed.
        wrapper.productsError = StoreKitError.notAvailableInStorefront

        do {
            _ = try await facade.purchase(storeId: "com.app.pro")
            XCTFail("Expected purchase to throw when the product load fails")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .storeProductNotAvailable)
        } catch {
            XCTFail("Raw store errors must never reach the integrator: \(error)")
        }
    }

    func testPurchaseMapsAnUnnamedProductLoadFailure() async {
        wrapper.productsError = MockError.stubbed

        do {
            _ = try await facade.purchase(storeId: "com.app.pro")
            XCTFail("Expected purchase to throw when the product load fails")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .storeProductsLoadingFailed)
            XCTAssertEqual(error.error as? MockError, .stubbed, "the underlying store error must stay reachable")
        } catch {
            XCTFail("Raw store errors must never reach the integrator: \(error)")
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

// MARK: - restore without an unnecessary auth prompt

final class StoreKitRestoreTests: XCTestCase {

    private func transaction(id: String) -> Qonversion.Transaction {
        Qonversion.Transaction(id: id, productId: "com.app.pro")
    }

    func testRestoreWithLocalTransactionsNeverSyncs() async throws {
        // AppStore.sync() shows an App Store authentication prompt: asking for
        // it when the device already knows the purchases is a UX regression.
        var syncCallsCount = 0
        let local: [Qonversion.Transaction] = [transaction(id: "t1")]

        let restored = try await StoreKitWrapper.restoreTransactions(
            localTransactions: { local },
            sync: { syncCallsCount += 1 }
        )

        XCTAssertEqual(restored.map(\.id), ["t1"])
        XCTAssertEqual(syncCallsCount, 0)
    }

    func testEmptyStoreFallsBackToSyncOnce() async throws {
        var syncCallsCount = 0
        var afterSync: [Qonversion.Transaction] = []

        let restored = try await StoreKitWrapper.restoreTransactions(
            localTransactions: { afterSync },
            sync: {
                syncCallsCount += 1
                afterSync = [self.transaction(id: "synced-1")]
            }
        )

        XCTAssertEqual(syncCallsCount, 1)
        XCTAssertEqual(restored.map(\.id), ["synced-1"])
    }

    func testSyncFailurePropagatesAsAnSDKError() async {
        // restore() is a public entry point: a raw store error would defeat
        // the `catch let error as QonversionError` the SDK documents.
        do {
            _ = try await StoreKitWrapper.restoreTransactions(
                localTransactions: { [] },
                sync: { throw MockError.stubbed }
            )
            XCTFail("Expected the store error to propagate")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .restoreFailed)
            XCTAssertEqual(error.error as? MockError, .stubbed, "the underlying store error must stay reachable")
        } catch {
            XCTFail("Raw store errors must never reach the integrator: \(error)")
        }
    }

    func testACancelledSignInIsNamedTheSameWayAsACancelledPurchase() async {
        // AppStore.sync() shows the App Store authentication prompt; backing
        // out of it is a cancellation, not a failure.
        do {
            _ = try await StoreKitWrapper.restoreTransactions(
                localTransactions: { [] },
                sync: { throw StoreKitError.userCancelled }
            )
            XCTFail("Expected the cancellation to propagate")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseCancelled)
        } catch {
            XCTFail("Raw store errors must never reach the integrator: \(error)")
        }
    }

    func testACancelledRunIsNotNamedARestoreFailure() async {
        // A run abandoned because the SDK switched users did not fail — and a
        // bare CancellationError no `catch let error as QonversionError` can
        // classify must never reach the host either.
        do {
            _ = try await StoreKitWrapper.restoreTransactions(
                localTransactions: { [] },
                sync: { throw CancellationError() }
            )
            XCTFail("Expected the cancellation to propagate")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .cancelled)
        } catch {
            XCTFail("Raw cancellation must never reach the integrator: \(error)")
        }
    }

    func testAnSDKErrorFromTheSyncIsNotWrappedAgain() async {
        do {
            _ = try await StoreKitWrapper.restoreTransactions(
                localTransactions: { [] },
                sync: { throw QonversionError(type: .purchaseCancelled) }
            )
            XCTFail("Expected the error to propagate")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseCancelled)
            XCTAssertNil(error.error, "an already classified error must pass through untouched")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// MARK: - typed purchase failures

final class StoreKitPurchaseFailureMappingTests: XCTestCase {

    func testStoreKitErrorsMapToTypedFailures() {
        XCTAssertEqual(StoreKitPurchaseOutcome.failureType(for: StoreKitError.userCancelled), .purchaseCancelled)
        XCTAssertEqual(StoreKitPurchaseOutcome.failureType(for: StoreKitError.notAvailableInStorefront), .storeProductNotAvailable)
        XCTAssertEqual(StoreKitPurchaseOutcome.failureType(for: StoreKitError.notEntitled), .paymentNotAllowed)
        XCTAssertEqual(StoreKitPurchaseOutcome.failureType(for: StoreKitError.networkError(URLError(.timedOut))), .purchaseFailed)
    }

    func testProductPurchaseErrorsMapToTypedFailures() {
        XCTAssertEqual(StoreKitPurchaseOutcome.failureType(for: StoreKit.Product.PurchaseError.productUnavailable), .storeProductNotAvailable)
        XCTAssertEqual(StoreKitPurchaseOutcome.failureType(for: StoreKit.Product.PurchaseError.purchaseNotAllowed), .paymentNotAllowed)
        XCTAssertEqual(StoreKitPurchaseOutcome.failureType(for: StoreKit.Product.PurchaseError.invalidOfferIdentifier), .purchaseFailed)
    }

    func testAnUnknownFailureStaysPurchaseFailedAndKeepsTheUnderlyingError() throws {
        let error = try XCTUnwrap(StoreKitPurchaseOutcome.failed(MockError.stubbed).qonversionError())

        XCTAssertEqual(error.type, .purchaseFailed)
        XCTAssertEqual(error.error as? MockError, .stubbed, "the underlying store error must stay reachable")
    }

    func testStoreOptionsCarryQuantityAndPromoOffer() {
        let promoOffer = Qonversion.PromotionalOffer(offerId: "offer1", keyId: "KEY", nonce: UUID(), signature: Data([0x01]), timestamp: 1)
        let options = Qonversion.PurchaseOptions(quantity: 3, promoOffer: promoOffer)

        let storeOptions: Set<StoreKit.Product.PurchaseOption> = StoreKitWrapper.storeOptions(for: options)

        XCTAssertTrue(storeOptions.contains(.quantity(3)))
        XCTAssertEqual(storeOptions.count, 2)
    }

    func testStoreOptionsIgnoreAWinBackOfferWithoutAStoreObject() {
        // A hand-built offer carries no StoreKit object, so there is nothing
        // to hand to the store — and nothing must be invented.
        let period = Qonversion.Product.SubscriptionPeriod(unit: .month, value: 1)
        let winBackOffer = Qonversion.Product.SubscriptionOffer(id: "wb1", type: .winBack, price: 1, displayPrice: "$1", period: period, periodCount: 1, paymentMode: .payAsYouGo)
        let options = Qonversion.PurchaseOptions(winBackOffer: winBackOffer)

        let storeOptions: Set<StoreKit.Product.PurchaseOption> = StoreKitWrapper.storeOptions(for: options)

        XCTAssertTrue(storeOptions.isEmpty)
        XCTAssertEqual(options.winBackOffer?.type, .winBack)
    }
}
