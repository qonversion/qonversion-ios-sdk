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

    private func makeProcessor(retriableRequestKinds: [Request.Kind] = []) -> RequestProcessor {
        RequestProcessor(
            baseURL: baseURL,
            networkProvider: networkProvider,
            headersBuilder: headersBuilder,
            errorHandler: errorHandler,
            decoder: responseDecoder,
            retriableRequestKinds: retriableRequestKinds,
            requestsStorage: requestsStorage,
            rateLimiter: rateLimiter
        )
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
            request: .createPurchase(userId: "u", body: ["app_store_data": ["transaction_id": "t1"] as RequestBodyDict]),
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
            request: .createPurchase(userId: "u", body: ["price": "9.99", "app_store_data": ["transaction_id": "t1"] as RequestBodyDict]),
            responseType: EmptyApiResponse.self
        )

        XCTAssertEqual(requestsStorage.storedRequests.count, 1)
        XCTAssertEqual(requestsStorage.storedRequests.first?.url, "https://api.qonversion.io/v3/users/u/purchases")
        XCTAssertEqual(requestsStorage.storedRequests.first?.method, "POST")
        XCTAssertEqual(requestsStorage.storedRequests.first?.dedupKey, "createPurchase-u-t1",
                       "the transaction id keys the dedup so the same purchase never queues twice")
    }

    func testSamePurchaseFailingTwiceIsQueuedOnce() async {
        networkProvider.error = URLError(.notConnectedToInternet)
        let processor = makeProcessor(retriableRequestKinds: [.createPurchase])
        let request = Request.createPurchase(userId: "u", body: ["price": "9.99", "app_store_data": ["transaction_id": "t1"] as RequestBodyDict])

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
            _ = try await processor.process(request: .getProducts(userId: "u"), responseType: ProcessorTestPayload.self)
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
