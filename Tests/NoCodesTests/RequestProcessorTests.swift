//
//  RequestProcessorTests.swift
//  NoCodesTests
//
//  The real RequestProcessor wired with the real error handler, decoder and
//  rate limiter — only the transport is stubbed.
//

import XCTest
@testable import NoCodes

private struct ProcessorTestPayload: Decodable, Equatable {
    let id: String
}

/// Queued transport results. Every response is consumed once; the last one is
/// repeated when the queue runs dry so latch tests can keep sending.
private final class StubNetworkProvider: NetworkProviderInterface, @unchecked Sendable {

    private let lock = NSLock()
    private var queuedResults: [Result<(Data, URLResponse), Error>] = []
    private var recordedRequests: [URLRequest] = []

    var sentRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }

        return recordedRequests
    }

    var sentRequestsCount: Int {
        return sentRequests.count
    }

    func enqueue(statusCode: Int, body: String) {
        let url = URL(string: "https://api2.qonversion.io/")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        let data: Data = Data(body.utf8)
        let result: Result<(Data, URLResponse), Error> = .success((data, response))

        lock.lock()
        defer { lock.unlock() }

        queuedResults.append(result)
    }

    func enqueue(failure: Error) {
        let result: Result<(Data, URLResponse), Error> = .failure(failure)

        lock.lock()
        defer { lock.unlock() }

        queuedResults.append(result)
    }

    func send(request: URLRequest) async throws -> (Data, URLResponse) {
        let result: Result<(Data, URLResponse), Error> = nextResult(for: request)

        return try result.get()
    }

    /// Kept synchronous so the lock is never held across a suspension point.
    private func nextResult(for request: URLRequest) -> Result<(Data, URLResponse), Error> {
        lock.lock()
        defer { lock.unlock() }

        recordedRequests.append(request)
        if queuedResults.count > 1 {
            return queuedResults.removeFirst()
        }
        if let last = queuedResults.first {
            return last
        }

        let error = NSError(domain: "StubNetworkProvider", code: -1, userInfo: nil)

        return .failure(error)
    }
}

private final class StubHeadersBuilder: HeadersBuilderInterface, @unchecked Sendable {

    func addHeaders(to request: inout URLRequest) {
        request.addValue("stub", forHTTPHeaderField: "X-Test")
    }
}

final class RequestProcessorTests: XCTestCase {

    private let baseURL = "https://api2.qonversion.io/"

    // MARK: - Happy path

    func testDecodesSuccessfulResponseIntoTheRequestedType() async throws {
        let networkProvider = StubNetworkProvider()
        networkProvider.enqueue(statusCode: 200, body: #"{"id": "screen-1"}"#)
        let processor: RequestProcessor = makeProcessor(networkProvider: networkProvider)
        let request = Request.getScreen(id: "screen-1")

        let payload: ProcessorTestPayload = try await processor.process(request: request, responseType: ProcessorTestPayload.self)

        XCTAssertEqual(payload, ProcessorTestPayload(id: "screen-1"))
        XCTAssertEqual(networkProvider.sentRequestsCount, 1)
    }

    func testAppliesTheHeadersBuilderToEveryRequest() async throws {
        let networkProvider = StubNetworkProvider()
        networkProvider.enqueue(statusCode: 200, body: #"{"id": "screen-1"}"#)
        let processor: RequestProcessor = makeProcessor(networkProvider: networkProvider)
        let request = Request.getScreen(id: "screen-1")

        _ = try await processor.process(request: request, responseType: ProcessorTestPayload.self)

        let sent: URLRequest = try XCTUnwrap(networkProvider.sentRequests.first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Test"), "stub")
    }

    // MARK: - 204

    func testEmptyResponseShortCircuitsDecodingFor204() async throws {
        let networkProvider = StubNetworkProvider()
        // A 204 carries no body at all — decoding it would fail.
        networkProvider.enqueue(statusCode: 204, body: "")
        let processor: RequestProcessor = makeProcessor(networkProvider: networkProvider)
        let events: [[String: AnyHashable]] = [["type": "screen_shown"]]
        let request = Request.sendScreenEvents(uid: "user-1", body: events)

        let response: EmptyApiResponse = try await processor.process(request: request, responseType: EmptyApiResponse.self)

        XCTAssertNotNil(response)
    }

    func testSuccessfulResponseWithUndecodableBodyFailsAsInvalidResponse() async throws {
        let networkProvider = StubNetworkProvider()
        networkProvider.enqueue(statusCode: 200, body: "not json at all")
        let processor: RequestProcessor = makeProcessor(networkProvider: networkProvider)
        let request = Request.getScreen(id: "screen-1")

        let error: NoCodesError = await captureError {
            let _: ProcessorTestPayload = try await processor.process(request: request, responseType: ProcessorTestPayload.self)
        }

        XCTAssertEqual(error.type, .invalidResponse)
    }

    // MARK: - Error extraction

    func testServerErrorIsReportedAsInternal() async throws {
        let error: NoCodesError = try await processError(statusCode: 500, body: "{}")

        XCTAssertEqual(error.type, .internal)
    }

    func testNotFoundIsReportedAsScreenNotFound() async throws {
        let error: NoCodesError = try await processError(statusCode: 404, body: "{}")

        XCTAssertEqual(error.type, .screenNotFound)
    }

    func testProjectKeyRejectionsAreReportedAsCritical() async throws {
        for statusCode in [401, 402, 403] {
            let error: NoCodesError = try await processError(statusCode: statusCode, body: "{}")

            XCTAssertEqual(error.type, .critical, "status code \(statusCode)")
        }
    }

    func testApiErrorMessageTravelsIntoTheError() async throws {
        let body = #"{"error": {"code": "1", "message": "Project key is invalid", "type": "auth"}}"#

        let error: NoCodesError = try await processError(statusCode: 401, body: body)

        XCTAssertTrue(error.message.contains("Project key is invalid"))
    }

    // MARK: - Sticky critical error

    func testCriticalErrorLatchesAndShortCircuitsEverySubsequentRequest() async throws {
        let networkProvider = StubNetworkProvider()
        networkProvider.enqueue(statusCode: 401, body: "{}")
        networkProvider.enqueue(statusCode: 200, body: #"{"id": "screen-1"}"#)
        let processor: RequestProcessor = makeProcessor(networkProvider: networkProvider)
        let first = Request.getScreen(id: "screen-1")
        let second = Request.getScreen(id: "screen-2")

        let firstError: NoCodesError = await captureError {
            let _: ProcessorTestPayload = try await processor.process(request: first, responseType: ProcessorTestPayload.self)
        }
        let secondError: NoCodesError = await captureError {
            let _: ProcessorTestPayload = try await processor.process(request: second, responseType: ProcessorTestPayload.self)
        }

        XCTAssertEqual(firstError.type, .critical)
        XCTAssertEqual(secondError.type, .critical)
        // The second request never reached the transport, even though the stub
        // had a successful response queued for it.
        XCTAssertEqual(networkProvider.sentRequestsCount, 1)
    }

    func testConcurrentRequestsLatchTheCriticalErrorWithoutRacing() async throws {
        let networkProvider = StubNetworkProvider()
        networkProvider.enqueue(statusCode: 403, body: "{}")
        // A permissive limiter keeps the rate limit out of this test.
        let rateLimiter = RateLimiter(maxRequestsPerSecond: 1000)
        let processor: RequestProcessor = makeProcessor(networkProvider: networkProvider, rateLimiter: rateLimiter)

        let failures: Int = await withTaskGroup(of: Bool.self) { group in
            for index in 0..<50 {
                group.addTask {
                    let request = Request.getScreen(id: "screen-\(index)")
                    do {
                        let _: ProcessorTestPayload = try await processor.process(request: request, responseType: ProcessorTestPayload.self)
                        return false
                    } catch let error as NoCodesError {
                        return error.type == .critical
                    } catch {
                        return false
                    }
                }
            }

            var count = 0
            for await isCritical in group where isCritical {
                count += 1
            }

            return count
        }

        XCTAssertEqual(failures, 50)
        XCTAssertNotNil(processor.criticalError)
    }

    // MARK: - Rate limiting

    func testRateLimitedRequestIsRejectedBeforeReachingTheTransport() async throws {
        let networkProvider = StubNetworkProvider()
        networkProvider.enqueue(statusCode: 200, body: #"{"id": "screen-1"}"#)
        let rateLimiter = RateLimiter(maxRequestsPerSecond: 1)
        let processor: RequestProcessor = makeProcessor(networkProvider: networkProvider, rateLimiter: rateLimiter)
        let request = Request.getScreen(id: "screen-1")

        _ = try await processor.process(request: request, responseType: ProcessorTestPayload.self)
        let error: NoCodesError = await captureError {
            let _: ProcessorTestPayload = try await processor.process(request: request, responseType: ProcessorTestPayload.self)
        }

        XCTAssertEqual(error.type, .rateLimitExceeded)
        XCTAssertEqual(networkProvider.sentRequestsCount, 1)
    }

    // MARK: - Transport failures

    func testTransportFailureIsReportedAsInvalidResponse() async throws {
        let networkProvider = StubNetworkProvider()
        let transportError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        networkProvider.enqueue(failure: transportError)
        let processor: RequestProcessor = makeProcessor(networkProvider: networkProvider)
        let request = Request.getScreen(id: "screen-1")

        let error: NoCodesError = await captureError {
            let _: ProcessorTestPayload = try await processor.process(request: request, responseType: ProcessorTestPayload.self)
        }

        XCTAssertEqual(error.type, .invalidResponse)
        XCTAssertNotNil(error.error)
    }

    func testUnbuildableRequestIsReportedAsInvalidRequest() async throws {
        let networkProvider = StubNetworkProvider()
        networkProvider.enqueue(statusCode: 200, body: "{}")
        // An unclosed IPv6 literal cannot be parsed into a URL at all.
        let processor: RequestProcessor = makeProcessor(networkProvider: networkProvider, baseURL: "https://[::1")
        let request = Request.getScreen(id: "screen-1")

        let error: NoCodesError = await captureError {
            let _: ProcessorTestPayload = try await processor.process(request: request, responseType: ProcessorTestPayload.self)
        }

        XCTAssertEqual(error.type, .invalidRequest)
        XCTAssertEqual(networkProvider.sentRequestsCount, 0)
    }

    // MARK: - Private

    private func makeProcessor(networkProvider: NetworkProviderInterface, rateLimiter: RateLimiterInterface? = nil, baseURL: String? = nil) -> RequestProcessor {
        let jsonDecoder = JSONDecoder()
        let responseDecoder = ResponseDecoder(decoder: jsonDecoder)
        let criticalCodes: [ResponseCode] = [.unauthorized, .paymentRequired, .forbidden]
        let errorHandler = NetworkErrorHandler(criticalErrorCodes: criticalCodes, decoder: responseDecoder)
        let headersBuilder = StubHeadersBuilder()
        let defaultLimiter = RateLimiter(maxRequestsPerSecond: 100)
        let limiter: RateLimiterInterface = rateLimiter ?? defaultLimiter
        let url: String = baseURL ?? self.baseURL

        return RequestProcessor(baseURL: url, networkProvider: networkProvider, headersBuilder: headersBuilder, errorHandler: errorHandler, decoder: responseDecoder, rateLimiter: limiter)
    }

    private func processError(statusCode: Int, body: String) async throws -> NoCodesError {
        let networkProvider = StubNetworkProvider()
        networkProvider.enqueue(statusCode: statusCode, body: body)
        let processor: RequestProcessor = makeProcessor(networkProvider: networkProvider)
        let request = Request.getScreen(id: "screen-1")

        return await captureError {
            let _: ProcessorTestPayload = try await processor.process(request: request, responseType: ProcessorTestPayload.self)
        }
    }

    private func captureError(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async -> NoCodesError {
        do {
            try await operation()
            XCTFail("expected the call to throw", file: file, line: line)
        } catch let error as NoCodesError {
            return error
        } catch {
            XCTFail("expected a NoCodesError, got \(error)", file: file, line: line)
        }

        return NoCodesError(type: .unknown)
    }
}
