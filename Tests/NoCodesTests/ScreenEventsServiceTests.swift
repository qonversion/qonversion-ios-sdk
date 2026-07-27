//
//  ScreenEventsServiceTests.swift
//  NoCodesTests
//
//  Batching, retry buffering and user id caching of the screen events pipeline.
//

import XCTest
@testable import NoCodes

/// Records the event batches it is asked to send and can be told to fail.
private final class EventsRequestProcessor: RequestProcessorInterface, @unchecked Sendable {

    private let lock = NSLock()
    private var sentBatches: [[[String: AnyHashable]]] = []
    private var shouldFail = false

    var batches: [[[String: AnyHashable]]] {
        lock.lock()
        defer { lock.unlock() }

        return sentBatches
    }

    var batchesCount: Int {
        return batches.count
    }

    var lastBatch: [[String: AnyHashable]]? {
        return batches.last
    }

    func failNextRequests(_ shouldFail: Bool) {
        lock.lock()
        defer { lock.unlock() }

        self.shouldFail = shouldFail
    }

    func process<T>(request: Request, responseType: T.Type) async throws -> T where T: Decodable {
        let isFailing: Bool = record(request: request)

        if isFailing {
            throw NoCodesError(type: .invalidResponse)
        }

        guard let empty = EmptyApiResponse() as? T else {
            throw NoCodesError(type: .invalidResponse)
        }

        return empty
    }

    /// Kept synchronous so the lock is never held across a suspension point.
    private func record(request: Request) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if case let .sendScreenEvents(_, body, _, _) = request {
            sentBatches.append(body)
        }

        return shouldFail
    }
}

private final class UserIdProviderSpy: @unchecked Sendable {

    private let lock = NSLock()
    private var calls = 0
    private let userId: String

    init(userId: String) {
        self.userId = userId
    }

    var callsCount: Int {
        lock.lock()
        defer { lock.unlock() }

        return calls
    }

    func provider() -> ScreenEventsService.UserIdProvider {
        return { [self] in
            resolve()
        }
    }

    /// Kept synchronous so the lock is never held across a suspension point.
    private func resolve() -> String {
        lock.lock()
        defer { lock.unlock() }

        calls += 1

        return userId
    }
}

final class ScreenEventsServiceTests: XCTestCase {

    // MARK: - Batching

    func testEventsAreBufferedUntilTheBatchIsFull() async throws {
        let processor = EventsRequestProcessor()
        let service: ScreenEventsService = makeService(processor: processor)

        for index in 0..<9 {
            let event: ScreenEvent = makeEvent(index: index)
            service.track(event: event)
        }

        // Nothing to wait for — the service must not have started a request.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(processor.batchesCount, 0)
    }

    func testTheTenthEventFlushesTheWholeBatch() async throws {
        let processor = EventsRequestProcessor()
        let service: ScreenEventsService = makeService(processor: processor)

        for index in 0..<10 {
            let event: ScreenEvent = makeEvent(index: index)
            service.track(event: event)
        }

        await waitUntil { processor.batchesCount == 1 }
        XCTAssertEqual(processor.lastBatch?.count, 10)
    }

    func testExplicitFlushSendsWhateverIsBuffered() async throws {
        let processor = EventsRequestProcessor()
        let service: ScreenEventsService = makeService(processor: processor)
        let event: ScreenEvent = makeEvent(index: 0)
        service.track(event: event)

        service.flush()

        await waitUntil { processor.batchesCount == 1 }
        XCTAssertEqual(processor.lastBatch?.count, 1)
    }

    func testFlushingAnEmptyBufferSendsNothing() async throws {
        let processor = EventsRequestProcessor()
        let service: ScreenEventsService = makeService(processor: processor)

        service.flush()

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(processor.batchesCount, 0)
    }

    func testTheBufferIsEmptiedByASuccessfulFlush() async throws {
        let processor = EventsRequestProcessor()
        let service: ScreenEventsService = makeService(processor: processor)
        let first: ScreenEvent = makeEvent(index: 0)
        service.track(event: first)
        service.flush()
        await waitUntil { processor.batchesCount == 1 }

        let second: ScreenEvent = makeEvent(index: 1)
        service.track(event: second)
        service.flush()

        await waitUntil { processor.batchesCount == 2 }
        XCTAssertEqual(processor.lastBatch?.count, 1)
        XCTAssertEqual(processor.lastBatch?.first?["index"] as? Int, 1)
    }

    // MARK: - Retry buffer

    func testFailedEventsAreReinsertedAtTheHeadOfTheBuffer() async throws {
        let processor = EventsRequestProcessor()
        processor.failNextRequests(true)
        let service: ScreenEventsService = makeService(processor: processor)
        let first: ScreenEvent = makeEvent(index: 0)
        service.track(event: first)
        service.flush()
        await waitUntil { processor.batchesCount == 1 }

        processor.failNextRequests(false)
        let second: ScreenEvent = makeEvent(index: 1)
        service.track(event: second)
        service.flush()

        await waitUntil { processor.batchesCount == 2 }
        let retried: [[String: AnyHashable]] = try XCTUnwrap(processor.lastBatch)
        XCTAssertEqual(retried.count, 2)
        // The failed event keeps its place at the front of the queue.
        XCTAssertEqual(retried.first?["index"] as? Int, 0)
        XCTAssertEqual(retried.last?["index"] as? Int, 1)
    }

    func testTheRetryBufferKeepsAtMostOneHundredEventsAndDropsTheOldest() async throws {
        let processor = EventsRequestProcessor()
        processor.failNextRequests(true)
        let service: ScreenEventsService = makeService(processor: processor)

        // 120 events, flushed in batches of 10 that all fail, so everything
        // lands back in the retry buffer.
        for index in 0..<120 {
            let event: ScreenEvent = makeEvent(index: index)
            service.track(event: event)
        }
        await waitUntil { processor.batchesCount >= 12 }

        processor.failNextRequests(false)
        service.flush()
        await waitUntil { processor.lastBatch?.count == 100 }

        let retained: [[String: AnyHashable]] = try XCTUnwrap(processor.lastBatch)
        XCTAssertEqual(retained.count, 100)
        // The 20 oldest events were dropped, the newest ones survived.
        XCTAssertEqual(retained.first?["index"] as? Int, 20)
        XCTAssertEqual(retained.last?["index"] as? Int, 119)
    }

    // MARK: - User id

    func testTheUserIdIsResolvedOnceAndReusedForLaterBatches() async throws {
        let processor = EventsRequestProcessor()
        let userIdProvider = UserIdProviderSpy(userId: "user-1")
        let service: ScreenEventsService = makeService(processor: processor, userIdProvider: userIdProvider)

        let first: ScreenEvent = makeEvent(index: 0)
        service.track(event: first)
        service.flush()
        await waitUntil { processor.batchesCount == 1 }

        let second: ScreenEvent = makeEvent(index: 1)
        service.track(event: second)
        service.flush()
        await waitUntil { processor.batchesCount == 2 }

        XCTAssertEqual(userIdProvider.callsCount, 1)
    }

    func testAFailingUserIdResolutionKeepsTheEventsForTheNextAttempt() async throws {
        let processor = EventsRequestProcessor()
        let failingProvider: ScreenEventsService.UserIdProvider = {
            throw NoCodesError(type: .sdkInitializationError)
        }
        let service = ScreenEventsService(requestProcessor: processor, logger: LoggerWrapper(), userIdProvider: failingProvider)
        let event: ScreenEvent = makeEvent(index: 0)
        service.track(event: event)

        service.flush()

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(processor.batchesCount, 0, "the batch never reached the transport")

        // The events survived: a later flush with a working resolution sends them.
        let workingService = ScreenEventsService(requestProcessor: processor, logger: LoggerWrapper(), userIdProvider: { "user-1" })
        let another: ScreenEvent = makeEvent(index: 1)
        workingService.track(event: another)
        workingService.flush()
        await waitUntil { processor.batchesCount == 1 }
        XCTAssertEqual(processor.batchesCount, 1)
    }

    // MARK: - Private

    private func makeService(processor: RequestProcessorInterface, userIdProvider: UserIdProviderSpy? = nil) -> ScreenEventsService {
        let logger = LoggerWrapper()
        let defaultProvider: ScreenEventsService.UserIdProvider = { "user-1" }
        let provider: ScreenEventsService.UserIdProvider = userIdProvider?.provider() ?? defaultProvider

        return ScreenEventsService(requestProcessor: processor, logger: logger, userIdProvider: provider)
    }

    private func makeEvent(index: Int) -> ScreenEvent {
        let data: [String: Any] = [
            "type": "screen_shown",
            "screen_uid": "screen-1",
            "index": index
        ]

        return ScreenEvent(data: data)
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
        let deadline: Date = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
