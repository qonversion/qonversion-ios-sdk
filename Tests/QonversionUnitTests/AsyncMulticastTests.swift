//
//  AsyncMulticastTests.swift
//  QonversionUnitTests
//
//  Direct contract tests for the fan-out primitive behind deferredPurchases(),
//  entitlementsUpdates() and promoPurchaseIntents().
//
//  Contract under test:
//    * every subscriber gets its own independent stream;
//    * a value produced while subscribers are listening is broadcast to all of
//      them, whatever the backlog policy is;
//    * .replayed keeps a value for every subscriber arriving inside the
//      lifetime — idempotent snapshots;
//    * .deliveredOnce hands a waiting value to the first subscriber that
//      arrives, and to nobody after it — events the host acts on;
//    * the delivery hook runs once, when a value first reaches a subscriber;
//    * the backlog is bounded by count and by age, and an infinite lifetime
//      makes a waiting value outwait anything.
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
        XCTAssertEqual(received, [2], "no backlog was asked for")
    }

    // MARK: - .replayed

    func testTheBacklogIsReplayedToASubscriberThatArrivesLater() async {
        let multicast = AsyncMulticast<Int>(backlog: .replayed)

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

    func testAReplayedValueReachesEverySubscriberArrivingLater() async {
        // The point of .replayed: the value is a snapshot, so reading it again
        // costs nothing and every late subscriber is entitled to it.
        let multicast = AsyncMulticast<Int>(backlog: .replayed)
        multicast.yield(1)

        let first = collect(multicast.stream())
        await waitUntil {
            let count: Int = await first.received.count
            return count == 1
        }
        let second = collect(multicast.stream())

        await waitUntil {
            let count: Int = await second.received.count
            return count == 1
        }
        let secondReceived: [Int] = await second.received
        XCTAssertEqual(secondReceived, [1])
    }

    func testALiveSubscriberDoesNotConsumeTheReplayOfALaterOne() async {
        let multicast = AsyncMulticast<Int>(backlog: .replayed)
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
        XCTAssertEqual(lateReceived, [1], "the late subscriber is owed the replay too")
        XCTAssertEqual(earlyReceived, [1], "the live subscriber must not be replayed its own value")
    }

    func testALiveSubscriberIsNeverDeliveredTheSameValueTwice() async {
        let multicast = AsyncMulticast<Int>(backlog: .replayed)
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
        let multicast = AsyncMulticast<Int>(backlog: .replayed)
        let survivor = collect(multicast.stream())
        // Kept alive on purpose: the point of the test is what the terminated
        // collector did NOT receive, which a released collector cannot report.
        let doomed = collect(multicast.stream())
        await waitUntil {
            let doomedAttached: Bool = await doomed.attached
            let survivorAttached: Bool = await survivor.attached
            return doomedAttached && survivorAttached
        }

        multicast.yield(7)
        await waitUntil {
            let doomedReceived: [Int] = await doomed.received
            let survivorReceived: [Int] = await survivor.received
            return doomedReceived == [7] && survivorReceived == [7]
        }

        await doomed.stop()
        // The unregistration happens on the stream's termination callback,
        // i.e. after the cancelled iteration unwinds.
        await waitUntil { multicast.subscriberCount == 1 }
        multicast.yield(8)

        await waitUntil {
            let received: [Int] = await survivor.received
            return received == [7, 8]
        }
        let survivorReceived: [Int] = await survivor.received
        let doomedReceived: [Int] = await doomed.received
        XCTAssertEqual(survivorReceived, [7, 8])
        XCTAssertEqual(doomedReceived, [7], "a terminated subscriber receives nothing after it stops")
        XCTAssertEqual(multicast.subscriberCount, 1, "the terminated subscriber is unregistered")
    }

    func testTheBacklogIsDeliveredBeforeAConcurrentLiveValue() async {
        // The hand-over happens under the same lock as the registration:
        // yielding it afterwards would let a value produced concurrently
        // overtake the backlog, so the host would see the launch purchase
        // AFTER the live one.
        let multicast = AsyncMulticast<Int>(backlog: .replayed)
        multicast.yield(1)
        multicast.yield(2)

        // Kept under the per-subscriber buffer (maxPending) so nothing is
        // dropped and the ORDER is what the assertion is about.
        let subscriber = collect(multicast.stream())
        for value in 3...8 {
            multicast.yield(value)
        }

        await waitUntil {
            let received: [Int] = await subscriber.received
            return received.last == 8
        }
        let received: [Int] = await subscriber.received
        XCTAssertEqual(received, Array(1...8), "the backlog always precedes the live values")
    }

    // MARK: - .deliveredOnce

    func testAWaitingValueIsHandedToTheFirstSubscriberAndToNobodyElse() async {
        let multicast = AsyncMulticast<Int>(backlog: .deliveredOnce)
        multicast.yield(1)

        let first = collect(multicast.stream())
        await waitUntil {
            let count: Int = await first.received.count
            return count == 1
        }
        let second = collect(multicast.stream())
        try? await Task.sleep(nanoseconds: 100_000_000)

        let firstReceived: [Int] = await first.received
        let secondReceived: [Int] = await second.received
        XCTAssertEqual(firstReceived, [1])
        XCTAssertEqual(secondReceived, [], "the value was already handed over")
    }

    func testALiveValueIsBroadcastToEverySubscriberAndNotKeptForLaterOnes() async {
        // Broadcast is not hand-off: N subscribers listening at the moment of
        // the value all get it, and it is spent afterwards.
        let multicast = AsyncMulticast<Int>(backlog: .deliveredOnce)
        let first = collect(multicast.stream())
        let second = collect(multicast.stream())
        await waitUntil {
            let firstAttached: Bool = await first.attached
            let secondAttached: Bool = await second.attached
            return firstAttached && secondAttached
        }

        multicast.yield(1)

        await waitUntil {
            let firstCount: Int = await first.received.count
            let secondCount: Int = await second.received.count
            return firstCount == 1 && secondCount == 1
        }
        let late = collect(multicast.stream())
        try? await Task.sleep(nanoseconds: 100_000_000)

        let firstReceived: [Int] = await first.received
        let secondReceived: [Int] = await second.received
        let lateReceived: [Int] = await late.received
        XCTAssertEqual(firstReceived, [1])
        XCTAssertEqual(secondReceived, [1])
        XCTAssertEqual(lateReceived, [], "a value that already reached its subscribers is never repeated")
    }

    func testEachWaitingValueIsHandedOverInOrderExactlyOnce() async {
        let multicast = AsyncMulticast<Int>(backlog: .deliveredOnce)
        multicast.yield(1)
        multicast.yield(2)
        multicast.yield(3)

        let subscriber = collect(multicast.stream())

        await waitUntil {
            let count: Int = await subscriber.received.count
            return count == 3
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let received: [Int] = await subscriber.received
        XCTAssertEqual(received, [1, 2, 3])
    }

    func testAValueWaitingWithoutADeadlineOutlivesAnyDelay() async {
        // The deferred-purchases wiring: an approval processed while nobody
        // listens must still be there when the host finally subscribes.
        let clock = MulticastTestClock(start: Date(timeIntervalSince1970: 1_000_000))
        let multicast = AsyncMulticast<Int>(
            backlog: .deliveredOnce,
            backlogLifetime: .infinity,
            now: { clock.now }
        )

        multicast.yield(1)
        clock.advance(by: 86_400)
        let subscriber = collect(multicast.stream())

        await waitUntil {
            let count: Int = await subscriber.received.count
            return count == 1
        }
        let received: [Int] = await subscriber.received
        XCTAssertEqual(received, [1], "a value with no deadline waits for its subscriber")
    }

    func testAWaitingValueStillExpiresWhenTheLifetimeIsFinite() async {
        let clock = MulticastTestClock(start: Date(timeIntervalSince1970: 1_000_000))
        let multicast = AsyncMulticast<Int>(
            backlog: .deliveredOnce,
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
        XCTAssertEqual(received, [2], "the expired value must not be handed over")
    }

    // MARK: - the delivery hook

    func testTheDeliveryHookRunsWhenTheValueIsBroadcastLive() async {
        let deliveries = MulticastDeliveryCounter()
        let multicast = AsyncMulticast<Int>(backlog: .deliveredOnce)
        let subscriber = collect(multicast.stream())
        await waitUntil {
            let attached: Bool = await subscriber.attached
            return attached
        }

        multicast.yield(1) { deliveries.record() }

        XCTAssertEqual(deliveries.count, 1)
    }

    func testTheDeliveryHookRunsWhenAWaitingValueIsHandedOver() async {
        let deliveries = MulticastDeliveryCounter()
        let multicast = AsyncMulticast<Int>(backlog: .deliveredOnce)

        multicast.yield(1) { deliveries.record() }
        XCTAssertEqual(deliveries.count, 0, "nobody has received it yet")

        let first = collect(multicast.stream())
        await waitUntil {
            let count: Int = await first.received.count
            return count == 1
        }
        _ = collect(multicast.stream())
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(deliveries.count, 1, "the hand-over is reported exactly once")
    }

    func testTheDeliveryHookNeverRunsForAValueThatExpired() async {
        let clock = MulticastTestClock(start: Date(timeIntervalSince1970: 1_000_000))
        let deliveries = MulticastDeliveryCounter()
        let multicast = AsyncMulticast<Int>(
            backlog: .deliveredOnce,
            backlogLifetime: 60,
            now: { clock.now }
        )

        multicast.yield(1) { deliveries.record() }
        clock.advance(by: 61)
        let subscriber = collect(multicast.stream())
        await waitUntil {
            let attached: Bool = await subscriber.attached
            return attached
        }
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(deliveries.count, 0, "an expired value was never delivered")
    }

    func testTheDeliveryHookOfAReplayedValueRunsOnlyOnTheFirstDelivery() async {
        let deliveries = MulticastDeliveryCounter()
        let multicast = AsyncMulticast<Int>(backlog: .replayed)

        multicast.yield(1) { deliveries.record() }

        let first = collect(multicast.stream())
        await waitUntil {
            let count: Int = await first.received.count
            return count == 1
        }
        let second = collect(multicast.stream())
        await waitUntil {
            let count: Int = await second.received.count
            return count == 1
        }

        XCTAssertEqual(deliveries.count, 1, "the replay is not a new delivery")
    }

    // MARK: - backlog bounds

    func testTheBacklogIsBoundedByCountAndKeepsTheNewestValues() async {
        let multicast = AsyncMulticast<Int>(backlog: .replayed)
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

    func testTheWaitingValuesAreBoundedByCountToo() async {
        // No subscriber ever showing up must not turn the buffer into an
        // unbounded event log.
        let multicast = AsyncMulticast<Int>(backlog: .deliveredOnce)
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
            backlog: .replayed,
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

    // MARK: - subscriber buffer headroom

    func testAFullBacklogLeavesRoomForLiveValuesBeforeTheSubscriberDrains() async {
        // With the per-subscriber buffer sized exactly like the backlog, a
        // full backlog leaves zero headroom: one live value arriving before
        // the new subscriber starts draining silently evicts the oldest
        // handed-over entry — in production a lost DeferredPurchase.
        let multicast = AsyncMulticast<Int>(backlog: .replayed)
        let backlogSize: Int = AsyncMulticast<Int>.maxPending
        for value in 1...backlogSize {
            multicast.yield(value)
        }

        // The stream registers (and is served) as it is built, but nothing
        // consumes it yet — the live value below lands in its buffer on top of
        // the whole backlog.
        let stream: AsyncStream<Int> = multicast.stream()
        multicast.yield(backlogSize + 1)

        let subscriber = collect(stream)
        let expected: [Int] = Array(1...(backlogSize + 1))
        await waitUntil {
            let received: [Int] = await subscriber.received
            return received == expected
        }

        let received: [Int] = await subscriber.received
        XCTAssertEqual(received, expected, "a live value must not evict the backlog the subscriber has not drained yet")
    }

    // MARK: - clearBacklog

    func testClearBacklogDropsAWaitingDeliveredOnceValueAndReturnsIt() async {
        let multicast = AsyncMulticast<Int>(backlog: .deliveredOnce, backlogLifetime: .infinity)
        multicast.yield(1)

        let dropped: [Int] = multicast.clearBacklog()

        XCTAssertEqual(dropped, [1])
        let subscriber = collect(multicast.stream())
        try? await Task.sleep(nanoseconds: 100_000_000)
        let received: [Int] = await subscriber.received
        XCTAssertEqual(received, [], "a subscriber arriving after clearBacklog must not receive the dropped value")
    }

    func testClearBacklogDropsAReplayedValueSoALaterSubscriberGetsNothing() async {
        let multicast = AsyncMulticast<Int>(backlog: .replayed)
        multicast.yield(1)

        multicast.clearBacklog()

        let subscriber = collect(multicast.stream())
        try? await Task.sleep(nanoseconds: 100_000_000)
        let received: [Int] = await subscriber.received
        XCTAssertEqual(received, [], "the cleared snapshot must not be replayed to a later subscriber")
    }

    func testClearBacklogDoesNotDisturbAValueAlreadyDeliveredToAnActiveSubscriber() async {
        let multicast = AsyncMulticast<Int>(backlog: .replayed)
        let subscriber = collect(multicast.stream())
        await waitUntil {
            let attached: Bool = await subscriber.attached
            return attached
        }
        multicast.yield(1)
        await waitUntil {
            let count: Int = await subscriber.received.count
            return count == 1
        }

        multicast.clearBacklog()

        let received: [Int] = await subscriber.received
        XCTAssertEqual(received, [1], "clearing the backlog must not retract a value the subscriber already has")
    }

    func testClearBacklogOnAnEmptyMulticastReturnsNothing() {
        let multicast = AsyncMulticast<Int>(backlog: .replayed)

        XCTAssertEqual(multicast.clearBacklog(), [])
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

/// Counts delivery-hook calls; the hook can run on any thread.
// @unchecked: the counter is lock-guarded.
private final class MulticastDeliveryCounter: @unchecked Sendable {

    private let lock = NSLock()
    private var calls: Int = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func record() {
        lock.lock()
        calls += 1
        lock.unlock()
    }
}
