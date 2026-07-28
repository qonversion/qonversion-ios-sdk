//
//  NoCodesServiceTests.swift
//  NoCodesTests
//
//  Caching, error classification and the fallback path of the screen service.
//

import XCTest
@testable import NoCodes

/// Replays canned JSON payloads and records what was asked for.
private final class SpyRequestProcessor: RequestProcessorInterface, @unchecked Sendable {

    private let lock = NSLock()
    private var payloads: [String] = []
    private var errors: [Error?] = []
    private var recordedRequests: [Request] = []

    var processedRequests: [Request] {
        lock.lock()
        defer { lock.unlock() }

        return recordedRequests
    }

    var processedRequestsCount: Int {
        return processedRequests.count
    }

    func enqueue(payload: String) {
        lock.lock()
        defer { lock.unlock() }

        payloads.append(payload)
        errors.append(nil)
    }

    func enqueue(error: Error) {
        lock.lock()
        defer { lock.unlock() }

        payloads.append("{}")
        errors.append(error)
    }

    func process<T>(request: Request, responseType: T.Type) async throws -> T where T: Decodable {
        let next: (payload: String, error: Error?) = nextResponse(for: request)
        let payload: String = next.payload

        if let error = next.error {
            throw error
        }

        let decoder = JSONDecoder()
        let data: Data = Data(payload.utf8)

        return try decoder.decode(T.self, from: data)
    }

    /// Kept synchronous so the lock is never held across a suspension point.
    private func nextResponse(for request: Request) -> (payload: String, error: Error?) {
        lock.lock()
        defer { lock.unlock() }

        recordedRequests.append(request)
        if payloads.count > 1 {
            let payload: String = payloads.removeFirst()
            let error: Error? = errors.removeFirst()

            return (payload, error)
        }

        let payload: String = payloads.first ?? "{}"
        let error: Error? = errors.first ?? nil

        return (payload, error)
    }
}

private final class StubFallbackService: FallbackServiceInterface, @unchecked Sendable {

    private let lock = NSLock()
    private var screensByContextKey: [String: NoCodesScreen] = [:]
    private var screensById: [String: NoCodesScreen] = [:]
    private var contextKeyLookups: [String] = []
    private var idLookups: [String] = []

    var contextKeyLookupsCount: Int {
        lock.lock()
        defer { lock.unlock() }

        return contextKeyLookups.count
    }

    var idLookupsCount: Int {
        lock.lock()
        defer { lock.unlock() }

        return idLookups.count
    }

    func register(screen: NoCodesScreen) {
        lock.lock()
        defer { lock.unlock() }

        if let contextKey: String = screen.contextKey {
          screensByContextKey[contextKey] = screen
        }
        screensById[screen.id] = screen
    }

    func loadScreen(withContextKey contextKey: String) -> NoCodesScreen? {
        lock.lock()
        defer { lock.unlock() }

        contextKeyLookups.append(contextKey)

        return screensByContextKey[contextKey]
    }

    func loadScreen(with id: String) -> NoCodesScreen? {
        lock.lock()
        defer { lock.unlock() }

        idLookups.append(id)

        return screensById[id]
    }
}

private final class StubImagePreloader: ImagePreloaderInterface, @unchecked Sendable {

    private let lock = NSLock()
    private var processedHtml: [String] = []

    var processedHtmlCount: Int {
        lock.lock()
        defer { lock.unlock() }

        return processedHtml.count
    }

    func preloadImages(in html: String) async -> String {
        record(html: html)

        return html + "<!-- preloaded -->"
    }

    /// Kept synchronous so the lock is never held across a suspension point.
    private func record(html: String) {
        lock.lock()
        defer { lock.unlock() }

        processedHtml.append(html)
    }
}

final class NoCodesServiceTests: XCTestCase {

    // MARK: - Cache

    func testSecondLoadByContextKeyIsServedFromTheCache() async throws {
        let processor = SpyRequestProcessor()
        processor.enqueue(payload: contextKeyPayload(id: "screen-1", contextKey: "main"))
        let service = NoCodesService(requestProcessor: processor)

        let first: NoCodesScreen = try await service.loadScreen(withContextKey: "main")
        let second: NoCodesScreen = try await service.loadScreen(withContextKey: "main")

        XCTAssertEqual(first.id, "screen-1")
        XCTAssertEqual(second.id, "screen-1")
        XCTAssertEqual(processor.processedRequestsCount, 1)
    }

    func testSecondLoadByIdIsServedFromTheCache() async throws {
        let processor = SpyRequestProcessor()
        processor.enqueue(payload: singleScreenPayload(id: "screen-1", contextKey: "main"))
        let service = NoCodesService(requestProcessor: processor)

        _ = try await service.loadScreen(with: "screen-1")
        _ = try await service.loadScreen(with: "screen-1")

        XCTAssertEqual(processor.processedRequestsCount, 1)
    }

    func testALoadByContextKeyAlsoWarmsTheIdCache() async throws {
        let processor = SpyRequestProcessor()
        processor.enqueue(payload: contextKeyPayload(id: "screen-1", contextKey: "main"))
        let service = NoCodesService(requestProcessor: processor)

        _ = try await service.loadScreen(withContextKey: "main")
        let byId: NoCodesScreen = try await service.loadScreen(with: "screen-1")

        XCTAssertEqual(byId.contextKey, "main")
        XCTAssertEqual(processor.processedRequestsCount, 1)
    }

    // MARK: - Preloading

    func testPreloadPopulatesBothCaches() async throws {
        let processor = SpyRequestProcessor()
        let payload = """
        [
          {"id": "screen-1", "body": "<html>one</html>", "context_key": "main"},
          {"id": "screen-2", "body": "<html>two</html>", "context_key": "onboarding"}
        ]
        """
        processor.enqueue(payload: payload)
        let service = NoCodesService(requestProcessor: processor)

        let preloaded: [NoCodesScreen] = try await service.preloadScreens()
        let byContextKey: NoCodesScreen = try await service.loadScreen(withContextKey: "onboarding")
        let byId: NoCodesScreen = try await service.loadScreen(with: "screen-1")

        XCTAssertEqual(preloaded.map(\.id), ["screen-1", "screen-2"])
        XCTAssertEqual(byContextKey.id, "screen-2")
        XCTAssertEqual(byId.contextKey, "main")
        XCTAssertEqual(processor.processedRequestsCount, 1)
    }

    func testPreloadRunsTheImagePreloaderOverEveryScreenAndCachesTheResult() async throws {
        let processor = SpyRequestProcessor()
        let payload = """
        [
          {"id": "screen-1", "body": "<html>one</html>", "context_key": "main"},
          {"id": "screen-2", "body": "<html>two</html>", "context_key": "onboarding"}
        ]
        """
        processor.enqueue(payload: payload)
        let imagePreloader = StubImagePreloader()
        let service = NoCodesService(requestProcessor: processor, fallbackService: nil, imagePreloader: imagePreloader)

        _ = try await service.preloadScreens()
        let cached: NoCodesScreen = try await service.loadScreen(withContextKey: "main")

        XCTAssertEqual(imagePreloader.processedHtmlCount, 2)
        XCTAssertEqual(cached.html, "<html>one</html><!-- preloaded -->")
    }

    func testOnDemandLoadsSkipImagePreloading() async throws {
        let processor = SpyRequestProcessor()
        processor.enqueue(payload: contextKeyPayload(id: "screen-1", contextKey: "main"))
        let imagePreloader = StubImagePreloader()
        let service = NoCodesService(requestProcessor: processor, fallbackService: nil, imagePreloader: imagePreloader)

        let screen: NoCodesScreen = try await service.loadScreen(withContextKey: "main")

        XCTAssertEqual(imagePreloader.processedHtmlCount, 0)
        XCTAssertEqual(screen.html, "<html>hi</html>")
    }

    // MARK: - Error surface

    func testScreenNotFoundIsSurfacedUnwrapped() async throws {
        let processor = SpyRequestProcessor()
        let notFound = NoCodesError(type: .screenNotFound)
        processor.enqueue(error: notFound)
        let fallbackService = StubFallbackService()
        let service = NoCodesService(requestProcessor: processor, fallbackService: fallbackService)

        let error: NoCodesError = await captureError {
            _ = try await service.loadScreen(withContextKey: "main")
        }

        XCTAssertEqual(error.type, .screenNotFound)
        // A genuinely absent screen must not consume the fallback file.
        XCTAssertEqual(fallbackService.contextKeyLookupsCount, 0)
    }

    func testEmptyScreenListIsReportedAsScreenNotFound() async throws {
        let processor = SpyRequestProcessor()
        processor.enqueue(payload: "[]")
        let service = NoCodesService(requestProcessor: processor)

        let error: NoCodesError = await captureError {
            _ = try await service.loadScreen(withContextKey: "main")
        }

        XCTAssertEqual(error.type, .screenNotFound)
    }

    func testAContextKeyFetchSkipsTheUnusableScreensAndServesTheRest() async throws {
        let processor = SpyRequestProcessor()
        processor.enqueue(payload: """
        [null,
         {"id": "broken", "body": null, "context_key": "main"},
         {"id": "good", "body": "<html>hi</html>", "context_key": "main"}]
        """)
        let service = NoCodesService(requestProcessor: processor)

        let screen: NoCodesScreen = try await service.loadScreen(withContextKey: "main")

        XCTAssertEqual(screen.id, "good")
    }

    func testAListOfOnlyUnusableScreensIsReportedAsScreenNotFound() async throws {
        let processor = SpyRequestProcessor()
        processor.enqueue(payload: #"[{"id": "broken", "body": null, "context_key": "main"}]"#)
        let service = NoCodesService(requestProcessor: processor)

        let error: NoCodesError = await captureError {
            _ = try await service.loadScreen(withContextKey: "main")
        }

        XCTAssertEqual(error.type, .screenNotFound)
    }

    func testPreloadSkipsTheUnusableScreens() async throws {
        let processor = SpyRequestProcessor()
        processor.enqueue(payload: """
        [{"id": "broken", "body": null, "context_key": "a"},
         {"id": "good", "body": "<html>hi</html>", "context_key": "b"}]
        """)
        let service = NoCodesService(requestProcessor: processor)

        let screens: [NoCodesScreen] = try await service.preloadScreens()

        XCTAssertEqual(screens.map { $0.id }, ["good"])
    }

    func testAScreenWithoutAContextKeyIsStillServedAndCachedById() async throws {
        let processor = SpyRequestProcessor()
        processor.enqueue(payload: #"{"id": "screen-1", "body": "<html>hi</html>", "context_key": null}"#)
        let service = NoCodesService(requestProcessor: processor)

        let screen: NoCodesScreen = try await service.loadScreen(with: "screen-1")
        _ = try await service.loadScreen(with: "screen-1")

        XCTAssertNil(screen.contextKey)
        XCTAssertEqual(processor.processedRequestsCount, 1, "the second load is served from the id cache")
    }

    func testOtherFailuresAreWrappedAsScreenLoadingFailed() async throws {
        let processor = SpyRequestProcessor()
        let productError = NoCodesError(type: .productNotFound)
        processor.enqueue(error: productError)
        let service = NoCodesService(requestProcessor: processor)

        let error: NoCodesError = await captureError {
            _ = try await service.loadScreen(withContextKey: "main")
        }

        XCTAssertEqual(error.type, .screenLoadingFailed)
    }

    // MARK: - Fallback

    func testNetworkFailureFallsBackToTheBundledScreenByContextKey() async throws {
        let processor = SpyRequestProcessor()
        let transportError = NoCodesError(type: .invalidResponse)
        processor.enqueue(error: transportError)
        let fallbackService = StubFallbackService()
        let fallbackScreen: NoCodesScreen = makeScreen(id: "fallback-1", contextKey: "main")
        fallbackService.register(screen: fallbackScreen)
        let service = NoCodesService(requestProcessor: processor, fallbackService: fallbackService)

        let screen: NoCodesScreen = try await service.loadScreen(withContextKey: "main")

        XCTAssertEqual(screen.id, "fallback-1")
        XCTAssertEqual(fallbackService.contextKeyLookupsCount, 1)
    }

    func testServerErrorFallsBackToTheBundledScreenById() async throws {
        let processor = SpyRequestProcessor()
        let response = HTTPURLResponse(url: URL(string: "https://api2.qonversion.io/")!, statusCode: 503, httpVersion: nil, headerFields: nil)!
        let userInfo: [String: Any] = ["response": response]
        let serverError = NSError(domain: "Server", code: 503, userInfo: userInfo)
        processor.enqueue(error: serverError)
        let fallbackService = StubFallbackService()
        let fallbackScreen: NoCodesScreen = makeScreen(id: "screen-1", contextKey: "main")
        fallbackService.register(screen: fallbackScreen)
        let service = NoCodesService(requestProcessor: processor, fallbackService: fallbackService)

        let screen: NoCodesScreen = try await service.loadScreen(with: "screen-1")

        XCTAssertEqual(screen.id, "screen-1")
        XCTAssertEqual(fallbackService.idLookupsCount, 1)
    }

    func testBusinessLogicFailuresDoNotConsumeTheFallback() async throws {
        let processor = SpyRequestProcessor()
        let businessError = NoCodesError(type: .productNotFound)
        processor.enqueue(error: businessError)
        let fallbackService = StubFallbackService()
        let fallbackScreen: NoCodesScreen = makeScreen(id: "fallback-1", contextKey: "main")
        fallbackService.register(screen: fallbackScreen)
        let service = NoCodesService(requestProcessor: processor, fallbackService: fallbackService)

        let error: NoCodesError = await captureError {
            _ = try await service.loadScreen(withContextKey: "main")
        }

        XCTAssertEqual(error.type, .screenLoadingFailed)
        XCTAssertEqual(fallbackService.contextKeyLookupsCount, 0)
    }

    func testMissingFallbackScreenStillReportsALoadingFailure() async throws {
        let processor = SpyRequestProcessor()
        let transportError = NoCodesError(type: .invalidResponse)
        processor.enqueue(error: transportError)
        let fallbackService = StubFallbackService()
        let service = NoCodesService(requestProcessor: processor, fallbackService: fallbackService)

        let error: NoCodesError = await captureError {
            _ = try await service.loadScreen(withContextKey: "main")
        }

        XCTAssertEqual(error.type, .screenLoadingFailed)
        XCTAssertEqual(fallbackService.contextKeyLookupsCount, 1)
    }

    func testFallbackScreensAreNotCachedSoTheNextLoadRetriesTheNetwork() async throws {
        let processor = SpyRequestProcessor()
        let transportError = NoCodesError(type: .invalidResponse)
        processor.enqueue(error: transportError)
        processor.enqueue(payload: contextKeyPayload(id: "screen-1", contextKey: "main"))
        let fallbackService = StubFallbackService()
        let fallbackScreen: NoCodesScreen = makeScreen(id: "fallback-1", contextKey: "main")
        fallbackService.register(screen: fallbackScreen)
        let service = NoCodesService(requestProcessor: processor, fallbackService: fallbackService)

        let first: NoCodesScreen = try await service.loadScreen(withContextKey: "main")
        let second: NoCodesScreen = try await service.loadScreen(withContextKey: "main")

        XCTAssertEqual(first.id, "fallback-1")
        XCTAssertEqual(second.id, "screen-1")
        XCTAssertEqual(processor.processedRequestsCount, 2)
    }

    // MARK: - Private

    private func contextKeyPayload(id: String, contextKey: String) -> String {
        return """
        [{"id": "\(id)", "body": "<html>hi</html>", "context_key": "\(contextKey)"}]
        """
    }

    private func singleScreenPayload(id: String, contextKey: String) -> String {
        return """
        {"id": "\(id)", "body": "<html>hi</html>", "context_key": "\(contextKey)"}
        """
    }

    private func makeScreen(id: String, contextKey: String) -> NoCodesScreen {
        return NoCodesScreen(id: id, html: "<html>fallback</html>", contextKey: contextKey)
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
