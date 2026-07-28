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
    private var sentUids: [String] = []
    private var shouldFail = false
    private var shouldStall = false

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

    var uids: [String] {
        lock.lock()
        defer { lock.unlock() }

        return sentUids
    }

    func failNextRequests(_ shouldFail: Bool) {
        lock.lock()
        defer { lock.unlock() }

        self.shouldFail = shouldFail
    }

    /// Keeps every request suspended, like a transport waiting on its timeout.
    func stallNextRequests(_ shouldStall: Bool) {
        lock.lock()
        defer { lock.unlock() }

        self.shouldStall = shouldStall
    }

    private var isStalling: Bool {
        lock.lock()
        defer { lock.unlock() }

        return shouldStall
    }

    func process<T>(request: Request, responseType: T.Type) async throws -> T where T: Decodable {
        let isFailing: Bool = record(request: request)

        while isStalling {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

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

        if case let .sendScreenEvents(uid, body, _, _) = request {
            sentBatches.append(body)
            sentUids.append(uid)
        }

        return shouldFail
    }
}

private final class UserIdProviderSpy: @unchecked Sendable {

    private let lock = NSLock()
    private var calls = 0
    private var userId: String
    private var shouldFail = false

    init(userId: String) {
        self.userId = userId
    }

    func setUserId(_ userId: String) {
        lock.lock()
        defer { lock.unlock() }

        self.userId = userId
    }

    func failNextResolutions(_ shouldFail: Bool) {
        lock.lock()
        defer { lock.unlock() }

        self.shouldFail = shouldFail
    }

    var callsCount: Int {
        lock.lock()
        defer { lock.unlock() }

        return calls
    }

    func provider() -> ScreenEventsService.UserIdProvider {
        return { [self] in
            try resolve()
        }
    }

    /// Kept synchronous so the lock is never held across a suspension point.
    private func resolve() throws -> String {
        lock.lock()
        defer { lock.unlock() }

        calls += 1

        if shouldFail {
            throw NoCodesError(type: .sdkInitializationError)
        }

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

        await waitUntilQuiet(processor)
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

    func testFlushingAnEmptyBufferSendsNothingAndLeavesTheServiceUsable() async throws {
        let processor = EventsRequestProcessor()
        let service: ScreenEventsService = makeService(processor: processor)

        service.flush()

        await waitUntilQuiet(processor)
        XCTAssertEqual(processor.batchesCount, 0)

        // Same instance: an empty flush must not latch the in-flight guard, or
        // every later event is silently swallowed for the rest of the process.
        let event: ScreenEvent = makeEvent(index: 0)
        service.track(event: event)
        service.flush()

        await waitUntil { processor.batchesCount == 1 }
        XCTAssertEqual(processor.lastBatch?.count, 1)
        XCTAssertEqual(processor.lastBatch?.first?["index"] as? Int, 0)
    }

    /// Every screen close flushes, and most of those flushes find an already
    /// drained buffer, so the empty case is the common one rather than the edge.
    func testRepeatedEmptyFlushesDoNotStopLaterEventsFromBeingSent() async throws {
        let processor = EventsRequestProcessor()
        let service: ScreenEventsService = makeService(processor: processor)

        for _ in 0..<5 {
            service.flush()
        }
        await waitUntilQuiet(processor)
        XCTAssertEqual(processor.batchesCount, 0)

        let event: ScreenEvent = makeEvent(index: 7)
        service.track(event: event)
        service.flush()

        await waitUntil { processor.batchesCount == 1 }
        XCTAssertEqual(processor.lastBatch?.first?["index"] as? Int, 7)
    }

    /// The batch-size auto flush goes through the same guard, so it has to
    /// survive an earlier empty flush too.
    func testAnEmptyFlushDoesNotBlockTheAutomaticBatchSizeFlush() async throws {
        let processor = EventsRequestProcessor()
        let service: ScreenEventsService = makeService(processor: processor)

        service.flush()
        await waitUntilQuiet(processor)

        for index in 0..<10 {
            let event: ScreenEvent = makeEvent(index: index)
            service.track(event: event)
        }

        await waitUntil { processor.batchesCount == 1 }
        XCTAssertEqual(processor.lastBatch?.count, 10)
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

        // 120 events, whose flushes all fail, so everything lands back in the
        // retry buffer. Trimming keeps the newest events, so intermediate
        // trims do not change the final expectation.
        for index in 0..<120 {
            let event: ScreenEvent = makeEvent(index: index)
            service.track(event: event)
        }
        await waitUntilQuiet(processor)

        // One more failing flush with nothing in flight: it takes the whole
        // buffer and re-inserts it trimmed to the cap.
        let batchesBeforeTrim: Int = processor.batchesCount
        service.flush()
        await waitUntil { processor.batchesCount > batchesBeforeTrim }
        await waitUntilQuiet(processor)

        processor.failNextRequests(false)
        service.flush()
        await waitUntil { processor.batchesCount > batchesBeforeTrim + 1 }

        let retained: [[String: AnyHashable]] = try XCTUnwrap(processor.lastBatch)
        XCTAssertEqual(retained.count, 100)
        // The 20 oldest events were dropped, the newest ones survived.
        XCTAssertEqual(retained.first?["index"] as? Int, 20)
        XCTAssertEqual(retained.last?["index"] as? Int, 119)
    }

    /// A flush that never comes back latches the in-flight guard, so every
    /// later flush returns at once and only `track` keeps running. Without a
    /// cap there, a long funnel behind a hanging request grows the buffer for
    /// as long as the request hangs.
    func testTrackingDropsTheOldestEventsOnceTheBufferIsFullWhileAFlushIsStalled() async throws {
        let processor = EventsRequestProcessor()
        processor.stallNextRequests(true)
        let service: ScreenEventsService = makeService(processor: processor)

        // The tenth event starts the flush that hangs.
        for index in 0..<10 {
            let event: ScreenEvent = makeEvent(index: index)
            service.track(event: event)
        }
        await waitUntil { processor.batchesCount == 1 }

        for index in 10..<210 {
            let event: ScreenEvent = makeEvent(index: index)
            service.track(event: event)
        }
        await waitUntilQuiet(processor)
        XCTAssertEqual(processor.batchesCount, 1, "every flush behind the stalled one is a no-op")

        processor.stallNextRequests(false)
        await flushUntilSent(service, processor, batchesCount: 2)

        let retained: [[String: AnyHashable]] = try XCTUnwrap(processor.lastBatch)
        XCTAssertEqual(retained.count, 100)
        // The oldest events were dropped, the newest ones survived.
        XCTAssertEqual(retained.first?["index"] as? Int, 110)
        XCTAssertEqual(retained.last?["index"] as? Int, 209)
    }

    // MARK: - User id

    func testEveryBatchIsPostedForTheUserResolvedAtFlushTime() async throws {
        let processor = EventsRequestProcessor()
        let userIdProvider = UserIdProviderSpy(userId: "user-1")
        let service: ScreenEventsService = makeService(processor: processor, userIdProvider: userIdProvider)

        let first: ScreenEvent = makeEvent(index: 0)
        service.track(event: first)
        service.flush()
        await waitUntil { processor.batchesCount == 1 }

        // The host app identified a different user between the batches.
        userIdProvider.setUserId("user-2")
        let second: ScreenEvent = makeEvent(index: 1)
        service.track(event: second)
        service.flush()
        await waitUntil { processor.batchesCount == 2 }

        // Resolved per flush, so the second batch reaches the new user instead
        // of the one the first batch was posted for.
        XCTAssertEqual(userIdProvider.callsCount, 2)
        XCTAssertEqual(processor.uids, ["user-1", "user-2"])
    }

    func testAFailingUserIdResolutionKeepsTheEventsForTheNextAttempt() async throws {
        let processor = EventsRequestProcessor()
        let userIdProvider = UserIdProviderSpy(userId: "user-1")
        userIdProvider.failNextResolutions(true)
        let service: ScreenEventsService = makeService(processor: processor, userIdProvider: userIdProvider)
        let event: ScreenEvent = makeEvent(index: 0)
        service.track(event: event)

        service.flush()

        await waitUntil { userIdProvider.callsCount == 1 }
        await waitUntilQuiet(processor)
        XCTAssertEqual(processor.batchesCount, 0, "the batch never reached the transport")

        // The very same service recovers: the buffered event is still there and
        // the next flush, with a working resolution, delivers it.
        userIdProvider.failNextResolutions(false)
        service.flush()

        await waitUntil { processor.batchesCount == 1 }
        let recovered: [[String: AnyHashable]] = try XCTUnwrap(processor.lastBatch)
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?["index"] as? Int, 0)
    }

    // MARK: - Private

    private func makeService(processor: RequestProcessorInterface, userIdProvider: UserIdProviderSpy? = nil) -> ScreenEventsService {
        let logger = LoggerWrapper()
        let defaultProvider: ScreenEventsService.UserIdProvider = { "user-1" }
        let provider: ScreenEventsService.UserIdProvider = userIdProvider?.provider() ?? defaultProvider

        return ScreenEventsService(requestProcessor: processor, logger: logger, userIdProvider: provider)
    }

    private func makeEvent(index: Int) -> ScreenEvent {
        let data: [String: AnyHashable] = [
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

    /// The in-flight guard is lowered asynchronously once a stalled request
    /// finally returns, so a flush issued right after the release can still be
    /// swallowed and has to be retried.
    private func flushUntilSent(_ service: ScreenEventsService, _ processor: EventsRequestProcessor, batchesCount: Int) async {
        await waitUntil {
            service.flush()

            return processor.batchesCount == batchesCount
        }
    }

    /// Polls until no request has been recorded for a few consecutive polls, so
    /// a negative assertion is not racing an in-flight flush.
    private func waitUntilQuiet(_ processor: EventsRequestProcessor, timeout: TimeInterval = 3.0) async {
        let deadline: Date = Date().addingTimeInterval(timeout)
        var lastSeen: Int = -1
        var stablePolls = 0
        while stablePolls < 5 && Date() < deadline {
            let current: Int = processor.batchesCount
            stablePolls = current == lastSeen ? stablePolls + 1 : 0
            lastSeen = current
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

// MARK: - Event payload

final class ScreenEventTests: XCTestCase {

    func testRawPayloadsKeepEveryHashableValue() {
        let rawData: [String: Any] = [
            "type": "screen_cta_tap",
            "index": 3,
            "ratio": 1.5,
            "enabled": true
        ]

        let event = ScreenEvent(rawData: rawData)

        XCTAssertEqual(event.toMap()["type"] as? String, "screen_cta_tap")
        XCTAssertEqual(event.toMap()["index"] as? Int, 3)
        XCTAssertEqual(event.toMap()["ratio"] as? Double, 1.5)
        XCTAssertEqual(event.toMap()["enabled"] as? Bool, true)
    }

    func testRawPayloadsDropValuesThatCannotTravelOnTheWire() {
        let rawData: [String: Any] = [
            "type": "screen_cta_tap",
            "callback": { () -> Void in }
        ]

        let event = ScreenEvent(rawData: rawData)

        XCTAssertEqual(event.toMap().count, 1)
        XCTAssertNil(event.toMap()["callback"])
        // The batch has to survive JSON serialization.
        let body: [String: Any] = ["events": [event.toMap()]]
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testTheMapIsThePayloadItself() {
        let data: [String: AnyHashable] = ["type": "screen_shown", "screen_uid": "screen-1"]

        let event = ScreenEvent(data: data)

        XCTAssertEqual(event.toMap(), data)
    }
}
