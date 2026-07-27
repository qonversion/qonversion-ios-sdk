//
//  AsyncMulticastTests.swift
//  QonversionUnitTests
//
//  Direct contract tests for the fan-out primitive behind deferredPurchases(),
//  entitlementsUpdates() and promoPurchaseIntents().
//
//  Backlog policy under test:
//    * every subscriber gets its own independent stream;
//    * with replaysBacklog, a value is replayed to EVERY subscriber arriving
//      inside the replay window, whether or not somebody was already listening
//      when it was produced;
//    * a subscriber reads the backlog once, at subscription, so a live
//      subscriber never sees a value twice;
//    * the backlog is bounded by count and by age.
//

import XCTest
@testable import Qonversion

final class AsyncMulticastTests: XCTestCase {

    private func collect<Element>(_ stream: AsyncStream<Element>) -> MulticastCollector<Element> {
        let collector = MulticastCollector(stream)
        return collector
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () async -> Bool) async {
        let deadline: Date = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let satisfied: Bool = await condition()
            if satisfied { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - fan-out

    func testEverySubscriberGetsEveryLiveValue() async {
        let multicast = AsyncMulticast<Int>()
        let first = collect(multicast.stream())
        let second = collect(multicast.stream())
        await waitUntil {
            let firstAttached: Bool = await first.attached
            let secondAttached: Bool = await second.attached
            return firstAttached && secondAttached
        }

        multicast.yield(1)
        multicast.yield(2)

        await waitUntil {
            let firstCount: Int = await first.received.count
            let secondCount: Int = await second.received.count
            return firstCount == 2 && secondCount == 2
        }
        let firstReceived: [Int] = await first.received
        let secondReceived: [Int] = await second.received
        XCTAssertEqual(firstReceived, [1, 2])
        XCTAssertEqual(secondReceived, [1, 2])
    }

    func testWithoutBacklogValuesYieldedToNobodyAreDropped() async {
        let multicast = AsyncMulticast<Int>()

        multicast.yield(1)
        let subscriber = collect(multicast.stream())
        await waitUntil {
            let attached: Bool = await subscriber.attached
            return attached
        }
        multicast.yield(2)

        await waitUntil {
            let count: Int = await subscriber.received.count
            return count == 1
        }
        let received: [Int] = await subscriber.received
        XCTAssertEqual(received, [2], "no replay was asked for")
    }

    // MARK: - backlog replay

    func testTheBacklogIsReplayedToASubscriberThatArrivesLater() async {
        let multicast = AsyncMulticast<Int>(replaysBacklog: true)

        multicast.yield(1)
        multicast.yield(2)
        let subscriber = collect(multicast.stream())

        await waitUntil {
            let count: Int = await subscriber.received.count
            return count == 2
        }
        let received: [Int] = await subscriber.received
        XCTAssertEqual(received, [1, 2])
    }

    func testALiveSubscriberDoesNotConsumeTheBacklogOfALaterOne() async {
        // The regression: the old implementation cleared the backlog as soon as
        // any subscriber was live, so the second subscriber got nothing.
        let multicast = AsyncMulticast<Int>(replaysBacklog: true)
        let early = collect(multicast.stream())
        await waitUntil {
            let attached: Bool = await early.attached
            return attached
        }

        multicast.yield(1)
        await waitUntil {
            let count: Int = await early.received.count
            return count == 1
        }

        let late = collect(multicast.stream())

        await waitUntil {
            let count: Int = await late.received.count
            return count == 1
        }
        let lateReceived: [Int] = await late.received
        let earlyReceived: [Int] = await early.received
        XCTAssertEqual(lateReceived, [1], "the late subscriber is owed the backlog too")
        XCTAssertEqual(earlyReceived, [1], "the live subscriber must not be replayed its own value")
    }

    func testALiveSubscriberIsNeverDeliveredTheSameValueTwice() async {
        let multicast = AsyncMulticast<Int>(replaysBacklog: true)
        let subscriber = collect(multicast.stream())
        await waitUntil {
            let attached: Bool = await subscriber.attached
            return attached
        }

        multicast.yield(1)
        multicast.yield(2)
        multicast.yield(3)

        await waitUntil {
            let count: Int = await subscriber.received.count
            return count == 3
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let received: [Int] = await subscriber.received
        XCTAssertEqual(received, [1, 2, 3])
    }

    func testATerminatedSubscriberStopsReceivingValues() async {
        let multicast = AsyncMulticast<Int>(replaysBacklog: true)
        let survivor = collect(multicast.stream())
        var doomed: MulticastCollector<Int>? = collect(multicast.stream())
        await waitUntil {
            let doomedAttached: Bool = await doomed?.attached ?? false
            let survivorAttached: Bool = await survivor.attached
            return doomedAttached && survivorAttached
        }

        await doomed?.stop()
        doomed = nil
        multicast.yield(7)

        await waitUntil {
            let received: [Int] = await survivor.received
            return received == [7]
        }
        let received: [Int] = await survivor.received
        XCTAssertEqual(received, [7])
    }

    // MARK: - backlog bounds

    func testTheBacklogIsBoundedByCountAndKeepsTheNewestValues() async {
        let multicast = AsyncMulticast<Int>(replaysBacklog: true)
        let overflow: Int = AsyncMulticast<Int>.maxPending + 3

        for value in 1...overflow {
            multicast.yield(value)
        }
        let subscriber = collect(multicast.stream())

        await waitUntil {
            let count: Int = await subscriber.received.count
            return count == AsyncMulticast<Int>.maxPending
        }
        let received: [Int] = await subscriber.received
        let expected: [Int] = Array(4...overflow)
        XCTAssertEqual(received, expected, "the oldest values are dropped first")
    }

    func testABacklogEntryOlderThanTheLifetimeIsNotReplayed() async {
        let clock = MulticastTestClock(start: Date(timeIntervalSince1970: 1_000_000))
        let multicast = AsyncMulticast<Int>(
            replaysBacklog: true,
            backlogLifetime: 60,
            now: { clock.now }
        )

        multicast.yield(1)
        clock.advance(by: 61)
        multicast.yield(2)
        let subscriber = collect(multicast.stream())

        await waitUntil {
            let count: Int = await subscriber.received.count
            return count == 1
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let received: [Int] = await subscriber.received
        XCTAssertEqual(received, [2], "the expired value must not be replayed")
    }

    func testTheDefaultBacklogLifetimeCoversTheLaunchWindow() {
        XCTAssertEqual(AsyncMulticast<Int>.defaultBacklogLifetime, 300)
    }
}

/// Collects everything a stream emits and reports when it actually attached.
private actor MulticastCollector<Element> {

    private(set) var received: [Element] = []
    private(set) var attached: Bool = false
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<Element>) {
        Task { await self.start(stream) }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func start(_ stream: AsyncStream<Element>) {
        attached = true
        task = Task {
            for await element in stream {
                self.append(element)
            }
        }
    }

    private func append(_ element: Element) {
        received.append(element)
    }
}

/// A hand-wound clock so backlog expiry is deterministic.
// @unchecked: `current` is only touched from the test's own serial flow.
private final class MulticastTestClock: @unchecked Sendable {

    private var current: Date

    init(start: Date) {
        self.current = start
    }

    var now: Date {
        return current
    }

    func advance(by interval: TimeInterval) {
        current = current.addingTimeInterval(interval)
    }
}
