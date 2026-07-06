//
//  PurchasesManagerTests.swift
//  QonversionUnitTests
//
//  Contract tests for the purchase flow (TDD — written before the implementation).
//
//  purchase(): user gate → store purchase → backend report → finish ONLY after
//  the backend confirmed. Observed out-of-band updates are reported but never
//  finished.
//

import XCTest
@testable import Qonversion

final class PurchasesManagerTests: XCTestCase {

    private var service: MockPurchasesService!
    private var facade: MockStoreKitFacade!
    private var userManager: MockUserManager!
    private var config: InternalConfig!
    private var manager: PurchasesManager!

    private let uid = "QON_buyer"

    override func setUp() {
        super.setUp()
        service = MockPurchasesService()
        facade = MockStoreKitFacade()
        userManager = MockUserManager()
        config = InternalConfig(userId: uid)
        userManager.user = try? JSONDecoder.qonversionTest.decode(
            Qonversion.User.self,
            from: Data(#"{"id": "QON_buyer", "created": 1700000000, "environment": "production"}"#.utf8))
        manager = PurchasesManager(
            purchasesService: service,
            storeKitFacade: facade,
            userManager: userManager,
            userIdProvider: config,
            logger: LoggerWrapper()
        )
    }

    override func tearDown() {
        manager = nil
        config = nil
        userManager = nil
        facade = nil
        service = nil
        super.tearDown()
    }

    private func makeProduct(storeId: String = "com.app.pro") -> Qonversion.Product {
        Qonversion.Product(qonversionId: "pro", storeId: storeId, offeringId: nil)
    }

    private func makeTransaction(id: String, jws: String? = "jws-proof") -> Qonversion.Transaction {
        Qonversion.Transaction(id: id, productId: "com.app.pro", jws: jws)
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - purchase happy path

    func testPurchaseGoesGateStorePurchaseReportThenFinish() async throws {
        facade.purchaseResult = makeTransaction(id: "t1")

        let transaction = try await manager.purchase(makeProduct(storeId: "com.app.pro"))

        XCTAssertEqual(userManager.obtainUserCallsCount, 1, "the user gate must be passed first")
        XCTAssertEqual(facade.purchasedStoreIds, ["com.app.pro"])
        XCTAssertEqual(service.sentTransactions.count, 1)
        XCTAssertEqual(service.sentTransactions.first?.transaction.id, "t1")
        XCTAssertEqual(service.sentTransactions.first?.userId, uid)
        XCTAssertEqual(facade.finishedTransactions.map(\.id), ["t1"], "finish only after the backend confirmed")
        XCTAssertEqual(transaction.id, "t1")
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

    func testPurchaseReportFailureLeavesTransactionUnfinished() async {
        facade.purchaseResult = makeTransaction(id: "t1")
        service.error = MockError.stubbed

        do {
            _ = try await manager.purchase(makeProduct())
            XCTFail("Expected purchase to throw when the backend report fails")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .purchaseReportingFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(facade.finishedTransactions.isEmpty,
                      "an unreported transaction must stay unfinished so it can be re-reported later")
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
        // No crash, no finish — the update will be re-observed/re-reported later.
    }
}
