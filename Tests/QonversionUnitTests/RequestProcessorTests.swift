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

    private func makeProcessor() -> RequestProcessor {
        RequestProcessor(
            baseURL: baseURL,
            networkProvider: networkProvider,
            headersBuilder: headersBuilder,
            errorHandler: errorHandler,
            decoder: responseDecoder,
            retriableRequestsList: [],
            requestsStorage: requestsStorage,
            rateLimiter: rateLimiter
        )
    }

    private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: baseURL)!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // MARK: - init / processStoredRequests

    func testInitFetchesAndCleansStoredRequestsWithoutResending() {
        requestsStorage.append(requests: [URLRequest(url: URL(string: "https://api.qonversion.io/v3/users/u")!)])

        _ = makeProcessor()

        // Fixates current behavior: processStoredRequests() is a stub (#warning in source) —
        // it fetches the stored requests and CLEANS the storage without resending anything.
        XCTAssertEqual(requestsStorage.cleanCallsCount, 1)
        XCTAssertTrue(networkProvider.sentRequests.isEmpty)
        XCTAssertTrue(requestsStorage.fetchRequests().isEmpty)
    }

    // MARK: - Success path

    func testSuccessPathDecodesResponse() async throws {
        networkProvider.responseData = Data("{\"id\": \"abc\"}".utf8)
        networkProvider.response = makeHTTPResponse(statusCode: 200)
        let processor = makeProcessor()

        let result = try await processor.process(request: .getUser(id: "u"), responseType: ProcessorTestPayload.self)

        XCTAssertEqual(result, ProcessorTestPayload(id: "abc"))
        XCTAssertEqual(networkProvider.sentRequests.count, 1)
        XCTAssertEqual(networkProvider.sentRequests.first?.url?.absoluteString, "https://api.qonversion.io/v3/users/u")
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
