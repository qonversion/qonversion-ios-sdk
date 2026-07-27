//
//  RequestProcessorTests.swift
//  QonversionUnitTests
//
//  Fixation tests for the real RequestProcessor wired with shared mocks.
//

import XCTest
@testable import Qonversion

private struct ProcessorTestPayload: Decodable, Equatable {
    let id: String
}

final class RequestProcessorTests: XCTestCase {

    private var networkProvider: MockNetworkProvider!
    private var headersBuilder: MockHeadersBuilder!
    private var errorHandler: MockNetworkErrorHandler!
    private var responseDecoder: MockResponseDecoder!
    private var requestsStorage: MockRequestsStorage!
    private var rateLimiter: MockRateLimiter!

    private let baseURL = "https://api.qonversion.io/"

    override func setUp() {
        super.setUp()
        networkProvider = MockNetworkProvider()
        headersBuilder = MockHeadersBuilder()
        errorHandler = MockNetworkErrorHandler()
        responseDecoder = MockResponseDecoder()
        requestsStorage = MockRequestsStorage()
        rateLimiter = MockRateLimiter()
    }

    override func tearDown() {
        networkProvider = nil
        headersBuilder = nil
        errorHandler = nil
        responseDecoder = nil
        requestsStorage = nil
        rateLimiter = nil
        super.tearDown()
    }

    private func makeProcessor(retriableRequestKinds: [Request.Kind] = [], reportsGate: TransactionReportsGate = TransactionReportsGate()) -> RequestProcessor {
        RequestProcessor(
            baseURL: baseURL,
            networkProvider: networkProvider,
            headersBuilder: headersBuilder,
            errorHandler: errorHandler,
            decoder: responseDecoder,
            retriableRequestKinds: retriableRequestKinds,
            requestsStorage: requestsStorage,
            rateLimiter: rateLimiter,
            delayCalculator: IncrementalDelayCalculator(),
            // The backoff itself is proven by IncrementalDelayCalculatorTests;
            // waiting it out here would only make the suite slow.
            transportRetryDelayCeiling: 0,
            reportsGate: reportsGate
        )
    }

    // MARK: - in-session transport retry (ObjC parity)

    func testAConnectionFailureIsRetriedWithinTheSameCall() async throws {
        // QNAPIClient.m:523-551 resent the request on a connection error
        // instead of failing the caller on the first flap.
        networkProvider.errorSequence = [URLError(.networkConnectionLost), nil]
        networkProvider.responseData = Data("{\"id\": \"abc\"}".utf8)
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        let processor = makeProcessor()

        let result = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)

        XCTAssertEqual(result, ProcessorTestPayload(id: "abc"))
        XCTAssertEqual(networkProvider.sentRequests.count, 2)
    }

    func testEveryConnectionClassErrorIsRetried() async throws {
        let connectionErrors: [URLError.Code] = [.notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed]

        for code in connectionErrors {
            networkProvider = MockNetworkProvider()
            networkProvider.errorSequence = [URLError(code), nil]
            networkProvider.responseData = Data("{\"id\": \"abc\"}".utf8)
            networkProvider.response = makeHTTPResponse(statusCode: 200)
            let processor = makeProcessor()

            _ = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)

            XCTAssertEqual(networkProvider.sentRequests.count, 2, "\(code) is a connection-class failure")
        }
    }

    func testTheRetriesAreBounded() async {
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor()

        do {
            _ = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)
            XCTFail("Expected the transport error to surface")
        } catch {
            XCTAssertEqual((error as? QonversionError)?.type, .invalidResponse)
        }

        XCTAssertEqual(networkProvider.sentRequests.count, RequestProcessor.maxTransportRetries + 1,
                       "a dead network must not be hammered without a bound")
    }

    func testEachRetryCarriesItsOwnAttemptNumber() async {
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor()

        _ = try? await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)

        let attempts: [String?] = networkProvider.sentRequests.map { $0.value(forHTTPHeaderField: "Attempt") }
        XCTAssertEqual(attempts, ["1", "2", "3", "4"], "the backend counts the attempts, like the ObjC client did")
    }

    func testANonTransportErrorIsNotRetried() async {
        networkProvider.error = MockError.stubbed
        let processor = makeProcessor()

        _ = try? await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)

        XCTAssertEqual(networkProvider.sentRequests.count, 1, "only connection-class failures are retried")
    }

    func testAnErrorResponseIsNeverRetried() async {
        // A response was received: the backend has the request, resending it
        // would duplicate the work.
        networkProvider.response = makeHTTPResponse(statusCode: 503)
        errorHandler.errorToReturn = QonversionError(type: .internal)
        let processor = makeProcessor()

        _ = try? await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)

        XCTAssertEqual(networkProvider.sentRequests.count, 1)
    }

    func testAnExhaustedRetryStillQueuesARetriableRequestOnce() async {
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])
        let body: RequestBodyDict = ["store_data": ["transaction_id": "t1"] as RequestBodyDict]

        _ = try? await processor.process(request: .createPurchase(userId: "u", body: body), responseType: EmptyApiResponse.self)

        XCTAssertEqual(requestsStorage.storedRequests.count, 1, "the offline queue is fed once, after the retries are spent")
    }

    func testTheRateLimiterIsConsultedOncePerCallNotPerRetry() async {
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor()

        _ = try? await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)

        XCTAssertEqual(rateLimiter.validatedRequests.count, 1, "a retry is not a new call")
    }

    // MARK: - replay vs the concurrent unfinished-transaction sweep

    func testTheReplaySkipsAnEntryRemovedWhileTheSnapshotWasBeingDrained() async {
        // The snapshot is not the queue: the sweep delivering the same
        // purchase evicts the queued copy while the previous entry is still
        // in flight.
        let first = StoredRequest(url: baseURL + "v4/users/u/purchases", method: "POST", body: nil, dedupKey: "first")
        let second = StoredRequest(url: baseURL + "v4/users/u/devices", method: "POST", body: nil, dedupKey: "second")
        requestsStorage.append(first)
        requestsStorage.append(second)
        let gate = ProcessorAsyncGate()
        networkProvider.onSend = { await gate.wait() }
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        let processor = makeProcessor()

        processor.processStoredRequests()
        await waitUntil { self.networkProvider.sentRequests.count == 1 }
        requestsStorage.remove(second)
        await gate.open()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(networkProvider.sentRequests.count, 1, "an entry no longer queued must not be resent")
    }

    func testTheReplaySkipsAPurchaseTheSweepAlreadyTook() async {
        let reportsGate = TransactionReportsGate()
        requestsStorage.append(StoredRequest(
            url: baseURL + "v4/users/u/purchases",
            method: "POST",
            body: nil,
            dedupKey: "createPurchase-u-tx1",
            transactionId: "tx1"
        ))
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        let processor = makeProcessor(reportsGate: reportsGate)
        // The sweep got there first.
        XCTAssertTrue(reportsGate.tryTake("tx1"))

        processor.processStoredRequests()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(networkProvider.sentRequests.isEmpty, "the sweep owns this transaction")
        XCTAssertEqual(requestsStorage.storedRequests.count, 1, "the entry stays queued for the sweep to evict on delivery")
    }

    func testADeliveredReplayKeepsTheTransactionTakenSoTheSweepSkipsIt() async {
        let reportsGate = TransactionReportsGate()
        requestsStorage.append(StoredRequest(
            url: baseURL + "v4/users/u/purchases",
            method: "POST",
            body: nil,
            dedupKey: "createPurchase-u-tx1",
            transactionId: "tx1"
        ))
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        let processor = makeProcessor(reportsGate: reportsGate)

        processor.processStoredRequests()
        await waitUntil { self.requestsStorage.storedRequests.isEmpty }

        XCTAssertEqual(networkProvider.sentRequests.count, 1)
        XCTAssertFalse(reportsGate.tryTake("tx1"), "the sweep must not post the same purchase again")
    }

    func testAFailedReplayReleasesTheTransactionForTheSweep() async {
        let reportsGate = TransactionReportsGate()
        requestsStorage.append(StoredRequest(
            url: baseURL + "v4/users/u/purchases",
            method: "POST",
            body: nil,
            dedupKey: "createPurchase-u-tx1",
            transactionId: "tx1"
        ))
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor(reportsGate: reportsGate)

        processor.processStoredRequests()
        await waitUntil { self.requestsStorage.storedRequests.first?.attempt == 2 }

        XCTAssertTrue(reportsGate.tryTake("tx1"), "an undelivered report must not block the sweep")
    }

    // MARK: - Attempt and Trigger headers (production parity)

    func testLiveRequestCarriesAttemptOneAndNoTriggerByDefault() async throws {
        let processor = makeProcessor()
        networkProvider.responseData = Data("{}".utf8)

        _ = try? await processor.process(request: Request.getProducts(), responseType: EmptyApiResponse.self)

        let sent = try XCTUnwrap(networkProvider.sentRequests.first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Attempt"), "1")
        XCTAssertNil(sent.value(forHTTPHeaderField: "Trigger"))
    }

    func testExplicitTriggerTravelsInTheHeader() async throws {
        let processor = makeProcessor()
        networkProvider.responseData = Data("{}".utf8)

        _ = try? await processor.process(request: Request.getProducts(), responseType: EmptyApiResponse.self, trigger: .restore)

        let sent = try XCTUnwrap(networkProvider.sentRequests.first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Trigger"), "Restore")
    }

    func testReplayedRequestCarriesIncrementedAttemptAndOriginalTrigger() async throws {
        let stored = StoredRequest(
            url: baseURL + "v4/users/u1/purchases",
            method: "POST",
            body: nil,
            dedupKey: nil,
            trigger: "Purchase",
            attempt: 1
        )
        requestsStorage.append(stored)
        let processor = makeProcessor()
        networkProvider.response = makeHTTPResponse(statusCode: 200)

        processor.processStoredRequests()
        await waitUntil { !self.networkProvider.sentRequests.isEmpty }

        let sent = try XCTUnwrap(networkProvider.sentRequests.first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Attempt"), "2")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Trigger"), "Purchase")
    }

    func testFailedReplayBumpsThePersistedAttempt() async throws {
        let stored = StoredRequest(
            url: baseURL + "v4/users/u1/purchases",
            method: "POST",
            body: nil,
            dedupKey: nil,
            trigger: "Purchase",
            attempt: 1
        )
        requestsStorage.append(stored)
        let processor = makeProcessor()
        networkProvider.response = makeHTTPResponse(statusCode: 500)

        processor.processStoredRequests()
        await waitUntil { self.requestsStorage.storedRequests.first?.attempt == 2 }

        XCTAssertEqual(requestsStorage.storedRequests.count, 1)
        XCTAssertEqual(requestsStorage.storedRequests.first?.attempt, 2, "the next replay must report the true attempt number")
        XCTAssertEqual(requestsStorage.storedRequests.first?.trigger, "Purchase")
    }

    func testRejectedRetriableRequestStoresItsTrigger() async {
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])
        networkProvider.response = makeHTTPResponse(statusCode: 503)
        errorHandler.errorToReturn = QonversionError(type: .internal)
        let request = Request.createPurchase(userId: "u1", body: ["price": "1"])

        _ = try? await processor.process(request: request, responseType: EmptyApiResponse.self, trigger: .restore)

        XCTAssertEqual(requestsStorage.storedRequests.first?.trigger, "Restore", "the replay must repeat the original flow's trigger")
    }

    func testEmptyBodyOnAnyTwoHundredIsSuccessForNoResponseRequests() async throws {
        let processor = makeProcessor()
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        networkProvider.responseData = Data()

        let result: EmptyApiResponse? = try? await processor.process(request: Request.detachUserFromExperiment(userId: "u1", experimentId: "e1"), responseType: EmptyApiResponse.self)

        XCTAssertNotNil(result, "an acknowledged no-response request must not fail on an empty body")
    }

    func testDeliveredPurchaseReportRemovesItsQueuedCopy() async {
        // The queued copy may sit under the PREVIOUS uid — matching goes by
        // transaction id, not by the full dedup key.
        requestsStorage.append(StoredRequest(url: "https://api2.qonversion.io/v4/users/OLD_UID/purchases", method: "POST", body: nil, dedupKey: "createPurchase-OLD_UID-tx42"))
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        networkProvider.responseData = Data("{}".utf8)
        let body: RequestBodyDict = ["store_data": ["transaction_id": "tx42"] as RequestBodyDict]

        _ = try? await processor.process(request: Request.createPurchase(userId: "NEW_UID", body: body), responseType: EmptyApiResponse.self)

        XCTAssertTrue(requestsStorage.storedRequests.isEmpty, "replaying the queued copy would double-report the purchase")
    }

    func testDeliveredReportDoesNotEvictAnUnrelatedPurchaseOfAHostileUid() async {
        // A backend-issued uid that ends in "-<transactionId>" must not make a
        // delivered report evict somebody else's queued purchase.
        requestsStorage.append(StoredRequest(
            url: "https://api2.qonversion.io/v4/users/QON_evil-tx42/purchases",
            method: "POST",
            body: nil,
            dedupKey: "createPurchase-QON_evil-tx42",
            transactionId: "other-transaction"
        ))
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        networkProvider.responseData = Data("{}".utf8)
        let body: RequestBodyDict = ["store_data": ["transaction_id": "tx42"] as RequestBodyDict]

        _ = try? await processor.process(request: Request.createPurchase(userId: "QON_NEW", body: body), responseType: EmptyApiResponse.self)

        XCTAssertEqual(requestsStorage.storedRequests.count, 1, "an unrelated queued purchase must survive")
    }

    func testQueuedPurchaseCarriesItsTransactionId() async {
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])
        networkProvider.error = URLError(.notConnectedToInternet)
        let body: RequestBodyDict = ["store_data": ["transaction_id": "tx42"] as RequestBodyDict]

        _ = try? await processor.process(request: Request.createPurchase(userId: "QON_u", body: body), responseType: EmptyApiResponse.self)

        XCTAssertEqual(requestsStorage.storedRequests.first?.transactionId, "tx42")
    }

    func testLegacyStoredRequestDecodesWithAttemptOne() throws {
        let legacyJson = #"{"url": "https://api2.qonversion.io/v4/users/u1/purchases", "method": "POST"}"#

        let stored: StoredRequest = try JSONDecoder().decode(StoredRequest.self, from: Data(legacyJson.utf8))

        XCTAssertEqual(stored.attempt, 1)
        XCTAssertNil(stored.trigger)
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: baseURL)!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // MARK: - offline replay

    func testInitDoesNotTouchStoredRequests() {
        requestsStorage.append(StoredRequest(url: "https://api.qonversion.io/v3/users/u/purchases", method: "POST", body: nil, dedupKey: nil))

        _ = makeProcessor()

        // Replay is explicit (assembly triggers it once per session).
        XCTAssertEqual(requestsStorage.cleanCallsCount, 0)
        XCTAssertTrue(networkProvider.sentRequests.isEmpty)
    }

    func testProcessStoredRequestsResendsWithFreshHeadersAndRemovesDeliveredOnes() async {
        let body = Data("{\"price\": \"9.99\"}".utf8)
        requestsStorage.append(StoredRequest(url: "https://api.qonversion.io/v3/users/u/purchases", method: "POST", body: body, dedupKey: nil))
        let processor = makeProcessor()

        processor.processStoredRequests()

        await waitUntil { self.networkProvider.sentRequests.count >= 1 && self.requestsStorage.fetchRequests().isEmpty }
        let resent = networkProvider.sentRequests.first
        XCTAssertEqual(resent?.url?.absoluteString, "https://api.qonversion.io/v3/users/u/purchases")
        XCTAssertEqual(resent?.httpMethod, "POST")
        XCTAssertEqual(resent?.httpBody, body)
        XCTAssertEqual(resent?.value(forHTTPHeaderField: "X-Test-Header"), "test", "headers are rebuilt fresh on resend")
        XCTAssertTrue(requestsStorage.fetchRequests().isEmpty, "a delivered request is removed from the queue")
    }

    func testProcessStoredRequestsKeepsRequestForNextSessionOnTransportFailure() async {
        requestsStorage.append(StoredRequest(url: "https://api.qonversion.io/v3/users/u/purchases", method: "POST", body: nil, dedupKey: nil))
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor()

        processor.processStoredRequests()

        await waitUntil { self.networkProvider.sentRequests.count >= 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(requestsStorage.fetchRequests().map(\.url), ["https://api.qonversion.io/v3/users/u/purchases"])
        XCTAssertEqual(requestsStorage.cleanCallsCount, 0, "the queue must not be dropped wholesale")
    }

    func testCleanDuringReplayStopsTheSendsAndKeepsTheQueueEmpty() async {
        // The user switched mid-replay: the queue belongs to the previous user
        // and was just cleaned — the snapshot must not resurrect it, neither by
        // sending the remaining entries nor by re-queueing a failed one.
        requestsStorage.append(StoredRequest(url: "https://api.qonversion.io/v3/users/u/purchases", method: "POST", body: nil, dedupKey: "first"))
        requestsStorage.append(StoredRequest(url: "https://api.qonversion.io/v3/users/u/devices", method: "POST", body: nil, dedupKey: "second"))
        let gate = ProcessorAsyncGate()
        networkProvider.onSend = { await gate.wait() }
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor()

        processor.processStoredRequests()
        await waitUntil { self.networkProvider.sentRequests.count == 1 }
        requestsStorage.clean()
        await gate.open()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(requestsStorage.fetchRequests().isEmpty, "a failed entry must not be re-appended to a cleaned queue")
        XCTAssertEqual(networkProvider.sentRequests.count, 1, "the remaining snapshot entries belong to the previous user")
    }

    func testProcessStoredRequestsSkipsWhenCriticalErrorLatched() async {
        requestsStorage.append(StoredRequest(url: "https://api.qonversion.io/v3/users/u/purchases", method: "POST", body: nil, dedupKey: nil))
        let processor = makeProcessor()
        processor.criticalError = QonversionError(type: .critical)

        processor.processStoredRequests()

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(networkProvider.sentRequests.isEmpty, "a revoked project key must stop the replay")
        XCTAssertEqual(requestsStorage.fetchRequests().count, 1)
    }

    func testProcessStoredRequestsKeepsRequestOn5xx() async {
        requestsStorage.append(StoredRequest(url: "https://api.qonversion.io/v3/users/u/purchases", method: "POST", body: nil, dedupKey: nil))
        networkProvider.response = makeHTTPResponse(statusCode: 503)
        let processor = makeProcessor()

        processor.processStoredRequests()

        await waitUntil { self.networkProvider.sentRequests.count >= 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(requestsStorage.fetchRequests().count, 1, "the backend did not process the request — it must stay queued")
    }

    func testProcessStoredRequestsRemovesRequestOnPermanent4xx() async {
        requestsStorage.append(StoredRequest(url: "https://api.qonversion.io/v3/users/u/purchases", method: "POST", body: nil, dedupKey: nil))
        networkProvider.response = makeHTTPResponse(statusCode: 400)
        let processor = makeProcessor()

        processor.processStoredRequests()

        await waitUntil { self.requestsStorage.fetchRequests().isEmpty }
        XCTAssertTrue(requestsStorage.fetchRequests().isEmpty, "a permanently rejected request must not loop forever")
    }

    func testServerErrorOnRetriableRequestIsStoredForReplay() async {
        networkProvider.response = makeHTTPResponse(statusCode: 503)
        errorHandler.errorToReturn = QonversionError(type: .internal)
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])

        _ = try? await processor.process(
            request: .createPurchase(userId: "u", body: ["store_data": ["transaction_id": "t1"] as RequestBodyDict]),
            responseType: EmptyApiResponse.self
        )

        XCTAssertEqual(requestsStorage.storedRequests.count, 1, "5xx means the backend did not process the purchase")
    }

    func testPurchaseWithoutTransactionIdGetsNoDedupKey() async {
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])

        // Two DIFFERENT purchases, both without a transaction id.
        _ = try? await processor.process(request: .createPurchase(userId: "u", body: ["price": "1"]), responseType: EmptyApiResponse.self)
        _ = try? await processor.process(request: .createPurchase(userId: "u", body: ["price": "2"]), responseType: EmptyApiResponse.self)

        XCTAssertEqual(requestsStorage.storedRequests.count, 2, "without a transaction id the dedup must not collapse distinct purchases")
        XCTAssertNil(requestsStorage.storedRequests.first?.dedupKey ?? nil)
    }

    // MARK: - storing failed retriable requests

    func testTransportFailureOfRetriableRequestIsStored() async {
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])

        _ = try? await processor.process(
            request: .createPurchase(userId: "u", body: ["price": "9.99", "store_data": ["transaction_id": "t1"] as RequestBodyDict]),
            responseType: EmptyApiResponse.self
        )

        XCTAssertEqual(requestsStorage.storedRequests.count, 1)
        XCTAssertEqual(requestsStorage.storedRequests.first?.url, "https://api.qonversion.io/v4/users/u/purchases")
        XCTAssertEqual(requestsStorage.storedRequests.first?.method, "POST")
        XCTAssertEqual(requestsStorage.storedRequests.first?.dedupKey, "createPurchase-u-t1",
                       "the transaction id keys the dedup so the same purchase never queues twice")
    }

    func testAFailedLiveRequestIsNotQueuedAfterAUserSwitch() async {
        // The request left for the PREVIOUS uid; the switch cleaned the queue
        // while it was in flight. Re-queueing it now would replay the previous
        // user's purchase in the next session, under the new uid.
        let gate = ProcessorAsyncGate()
        networkProvider.onSend = { await gate.wait() }
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])
        let body: RequestBodyDict = ["store_data": ["transaction_id": "t1"] as RequestBodyDict]

        let sending = Task {
            _ = try? await processor.process(request: .createPurchase(userId: "OLD_UID", body: body), responseType: EmptyApiResponse.self)
        }
        await waitUntil { self.networkProvider.sentRequests.count == 1 }
        requestsStorage.clean()
        await gate.open()
        _ = await sending.value

        XCTAssertTrue(requestsStorage.storedRequests.isEmpty, "the entry belongs to the previous user")
    }

    func testARejectedLiveRequestIsNotQueuedAfterAUserSwitch() async {
        // Same window, the 5xx branch: the backend answered "not processed"
        // for a request that belongs to the previous user.
        let gate = ProcessorAsyncGate()
        networkProvider.onSend = { await gate.wait() }
        networkProvider.response = makeHTTPResponse(statusCode: 503)
        errorHandler.errorToReturn = QonversionError(type: .internal)
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])
        let body: RequestBodyDict = ["store_data": ["transaction_id": "t1"] as RequestBodyDict]

        let sending = Task {
            _ = try? await processor.process(request: .createPurchase(userId: "OLD_UID", body: body), responseType: EmptyApiResponse.self)
        }
        await waitUntil { self.networkProvider.sentRequests.count == 1 }
        requestsStorage.clean()
        await gate.open()
        _ = await sending.value

        XCTAssertTrue(requestsStorage.storedRequests.isEmpty, "the entry belongs to the previous user")
    }

    func testSamePurchaseFailingTwiceIsQueuedOnce() async {
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])
        let request = Request.createPurchase(userId: "u", body: ["price": "9.99", "store_data": ["transaction_id": "t1"] as RequestBodyDict])

        _ = try? await processor.process(request: request, responseType: EmptyApiResponse.self)
        _ = try? await processor.process(request: request, responseType: EmptyApiResponse.self)

        XCTAssertEqual(requestsStorage.storedRequests.count, 1)
    }

    func testTransportFailureOfNonRetriableRequestIsNotStored() async {
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])

        _ = try? await processor.process(request: .getUser(id: "u"), responseType: EmptyApiResponse.self)

        XCTAssertTrue(requestsStorage.storedRequests.isEmpty)
    }

    func testHttpErrorOfRetriableRequestIsNotStored() async {
        // The backend answered — delivery succeeded, resending would duplicate.
        errorHandler.errorToReturn = QonversionError(type: .internal)
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])

        _ = try? await processor.process(
            request: .createPurchase(userId: "u", body: ["price": "9.99"]),
            responseType: EmptyApiResponse.self
        )

        XCTAssertTrue(requestsStorage.storedRequests.isEmpty)
    }

    // MARK: - Success path

    func testSuccessPathDecodesResponse() async throws {
        networkProvider.responseData = Data("{\"id\": \"abc\"}".utf8)
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        let processor = makeProcessor()

        let result = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)

        XCTAssertEqual(result, ProcessorTestPayload(id: "abc"))
        XCTAssertEqual(networkProvider.sentRequests.count, 1)
        XCTAssertEqual(networkProvider.sentRequests.first?.url?.absoluteString, "https://api.qonversion.io/v4/users/u")
        // Headers are added to the outgoing request via HeadersBuilder.
        XCTAssertEqual(headersBuilder.callsCount, 1)
        XCTAssertEqual(networkProvider.sentRequests.first?.value(forHTTPHeaderField: "X-Test-Header"), "test")
        // Error handler is consulted on every response.
        XCTAssertEqual(errorHandler.callsCount, 1)
        XCTAssertEqual(rateLimiter.validatedRequests, [.getUser(id: "u")])
    }

    // MARK: - Rate limiting

    func testRateLimitErrorIsThrownBeforeNetworkCall() async {
        rateLimiter.errorToReturn = QonversionError(type: .rateLimitExceeded)
        let processor = makeProcessor()

        do {
            _ = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)
            XCTFail("Expected rate limit error")
        } catch {
            XCTAssertEqual((error as? QonversionError)?.type, .rateLimitExceeded)
        }

        XCTAssertTrue(networkProvider.sentRequests.isEmpty)
        XCTAssertEqual(headersBuilder.callsCount, 0)
    }

    // MARK: - Transport error

    func testTransportErrorIsWrappedIntoInvalidResponse() async {
        networkProvider.error = MockError.stubbed
        let processor = makeProcessor()

        do {
            _ = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)
            XCTFail("Expected invalidResponse error")
        } catch {
            let qonversionError = error as? QonversionError
            XCTAssertEqual(qonversionError?.type, .invalidResponse)
            XCTAssertEqual(qonversionError?.error as? MockError, .stubbed)
        }
    }

    // MARK: - Handler-extracted errors

    func testHandlerExtractedErrorIsThrown() async {
        networkProvider.response = makeHTTPResponse(statusCode: 404)
        errorHandler.errorToReturn = QonversionError(type: .unknown, message: "not found")
        let processor = makeProcessor()

        do {
            _ = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)
            XCTFail("Expected handler error")
        } catch {
            let qonversionError = error as? QonversionError
            XCTAssertEqual(qonversionError?.type, .unknown)
            XCTAssertEqual(qonversionError?.message, "not found")
        }
        // Non-critical errors do not latch: a second call still reaches the network.
        errorHandler.errorToReturn = nil
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        networkProvider.responseData = Data("{\"id\": \"abc\"}".utf8)
        do {
            _ = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(networkProvider.sentRequests.count, 2)
    }

    // MARK: - Critical error latch

    func testCriticalErrorLatchesAndBlocksSubsequentRequests() async {
        networkProvider.response = makeHTTPResponse(statusCode: 401)
        errorHandler.errorToReturn = QonversionError(type: .critical, message: "unauthorized")
        let processor = makeProcessor()

        do {
            _ = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)
            XCTFail("Expected critical error")
        } catch {
            XCTAssertEqual((error as? QonversionError)?.type, .critical)
        }
        XCTAssertEqual(networkProvider.sentRequests.count, 1)

        // Even if the backend would now succeed, the processor throws immediately.
        errorHandler.errorToReturn = nil
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        networkProvider.responseData = Data("{\"id\": \"abc\"}".utf8)

        do {
            _ = try await processor.process(request: .getProducts(), responseType: ProcessorTestPayload.self)
            XCTFail("Expected latched critical error")
        } catch {
            let qonversionError = error as? QonversionError
            XCTAssertEqual(qonversionError?.type, .critical)
            XCTAssertEqual(qonversionError?.message, "unauthorized")
        }
        // Fixates current behavior: the latch is checked before the rate limiter and
        // the network — neither is touched for the second request, and it stays
        // latched forever (no reset path exists).
        XCTAssertEqual(networkProvider.sentRequests.count, 1)
        XCTAssertEqual(rateLimiter.validatedRequests.count, 1)
    }

    // MARK: - 204 No Content + EmptyApiResponse

    func testNoContentWithEmptyApiResponseSkipsDecoding() async throws {
        networkProvider.response = makeHTTPResponse(statusCode: 204)
        networkProvider.responseData = Data()
        // Prove the decoder is bypassed: it would throw if called.
        responseDecoder.error = MockError.stubbed
        let processor = makeProcessor()

        let result = try await processor.process(request: .entitlements(userId: "u"), responseType: EmptyApiResponse.self)

        XCTAssertTrue(type(of: result) == EmptyApiResponse.self)
        XCTAssertEqual(networkProvider.sentRequests.count, 1)
    }

    func testNoContentWithOtherTypeStillGoesThroughDecoder() async {
        // Fixates current behavior: the 204 short-circuit only applies when the expected
        // type is exactly EmptyApiResponse; any other type is decoded from the (empty)
        // body and fails with .invalidResponse.
        networkProvider.response = makeHTTPResponse(statusCode: 204)
        networkProvider.responseData = Data()
        let processor = makeProcessor()

        do {
            _ = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)
            XCTFail("Expected decoding failure")
        } catch {
            XCTAssertEqual((error as? QonversionError)?.type, .invalidResponse)
        }
    }

    // MARK: - Decode failure

    func testDecodeFailureIsWrappedIntoInvalidResponse() async {
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        networkProvider.responseData = Data("{\"unexpected\": true}".utf8)
        let processor = makeProcessor()

        do {
            _ = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)
            XCTFail("Expected invalidResponse error")
        } catch {
            let qonversionError = error as? QonversionError
            XCTAssertEqual(qonversionError?.type, .invalidResponse)
            XCTAssertTrue(qonversionError?.error is DecodingError)
        }
    }
}

/// A reusable async gate: wait() suspends until open() is called.
private actor ProcessorGateStorage {
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

private final class ProcessorAsyncGate: @unchecked Sendable {
    private let storage = ProcessorGateStorage()
    func open() async { await storage.open() }
    func wait() async { await storage.wait() }
}
