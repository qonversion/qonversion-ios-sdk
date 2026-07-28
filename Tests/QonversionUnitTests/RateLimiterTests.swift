//
//  RateLimiterTests.swift
//  QonversionUnitTests
//
//  Fixation tests for RateLimiter. The limiter is keyed by request.hashValue
//  and allows up to maxRequestsPerSecond identical requests per sliding 1s window.
//

import XCTest
@testable import Qonversion

final class RateLimiterConcurrencyTests: XCTestCase {

    func testConcurrentValidationsCountExactlyTheLimitPerKey() async {
        // A limit of 1000 against 300 requests was never reached, so nothing
        // about the counting was pinned. Here every key is hammered far past
        // its limit: exactly `maxRequestsPerSecond` may pass, no more and no
        // fewer, whatever order the tasks run in.
        let limit = 5
        let keys = 3
        let attemptsPerKey = 100
        // A FROZEN clock: against the wall clock this assertion is a race —
        // 300 tasks on a loaded machine can straddle a window boundary and
        // legitimately admit more than the limit.
        let clock = RateLimiterFrozenClock(now: 1_700_000_000)
        let limiter = RateLimiter(maxRequestsPerSecond: UInt(limit), now: { clock.now })
        let allowed = RateLimiterAllowanceCounter()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<(keys * attemptsPerKey) {
                group.addTask {
                    let key = "user_\(index % keys)"
                    if limiter.validateRateLimit(for: .getUser(id: key)) == nil {
                        allowed.record(key)
                    }
                }
            }
        }

        let counts: [String: Int] = allowed.counts()
        XCTAssertEqual(counts, ["user_0": limit, "user_1": limit, "user_2": limit],
                       "the window must admit exactly the limit per key under concurrency")
        XCTAssertNil(limiter.validateRateLimit(for: .getUser(id: "fresh")), "an untouched key is unaffected")

        // ...and the window really does slide: past it the same key is
        // admitted again.
        clock.advance(by: 2)
        XCTAssertNil(limiter.validateRateLimit(for: .getUser(id: "user_0")))
    }
}

final class RateLimiterTests: XCTestCase {

    func testUnderLimitReturnsNil() {
        let limiter = RateLimiter(maxRequestsPerSecond: 3)
        let request = Request.getUser(id: "user1")

        XCTAssertNil(limiter.validateRateLimit(for: request))
        XCTAssertNil(limiter.validateRateLimit(for: request))
        XCTAssertNil(limiter.validateRateLimit(for: request))
    }

    func testAtLimitReturnsRateLimitExceededError() {
        let limiter = RateLimiter(maxRequestsPerSecond: 2)
        let request = Request.getUser(id: "user1")

        XCTAssertNil(limiter.validateRateLimit(for: request))
        XCTAssertNil(limiter.validateRateLimit(for: request))

        let error = limiter.validateRateLimit(for: request)
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.type, .rateLimitExceeded)
        XCTAssertEqual(error?.message, "Rate limit exceeded for the current request")
        XCTAssertNil(error?.error)
        XCTAssertNil(error?.additionalInfo)
    }

    func testExceededRequestIsNotSavedSoLimitStays() {
        let limiter = RateLimiter(maxRequestsPerSecond: 1)
        let request = Request.getUser(id: "user1")

        XCTAssertNil(limiter.validateRateLimit(for: request))
        // Rejected attempts are not recorded, they just keep failing within the window.
        XCTAssertNotNil(limiter.validateRateLimit(for: request))
        XCTAssertNotNil(limiter.validateRateLimit(for: request))
    }

    func testDifferentRequestIsUnaffected() {
        let limiter = RateLimiter(maxRequestsPerSecond: 1)
        let requestA = Request.getUser(id: "user1")
        let requestB = Request.getUser(id: "user2")
        let requestC = Request.getProducts()

        XCTAssertNil(limiter.validateRateLimit(for: requestA))
        XCTAssertNotNil(limiter.validateRateLimit(for: requestA))

        // Requests with different params or different cases have different hashes
        // and independent limits.
        XCTAssertNil(limiter.validateRateLimit(for: requestB))
        XCTAssertNil(limiter.validateRateLimit(for: requestC))
    }

    func testAttachExperimentRequestsWithDifferentGroupIdsAreLimitedIndependently() {
        let limiter = RateLimiter(maxRequestsPerSecond: 1)
        let first = Request.attachUserToExperiment(userId: "u", experimentId: "e", groupId: "group1")
        let second = Request.attachUserToExperiment(userId: "u", experimentId: "e", groupId: "group2")

        XCTAssertNil(limiter.validateRateLimit(for: first))
        // A different group is a different request — it must not inherit the
        // first one's limit.
        XCTAssertNil(limiter.validateRateLimit(for: second))
    }

    func testTheGlobalPruneRunsOnceTheGuardElapsesSinceConstruction() {
        // The guard timestamp is anchored at construction, not at zero. With a
        // zero anchor the FIRST call always sweeps and re-anchors itself to
        // its own moment, so the next sweep is due 10s after that call instead
        // of 10s after the limiter was built — the stale bucket below survives.
        let clock = RateLimiterFrozenClock(now: 1_000)
        let limiter = RateLimiter(maxRequestsPerSecond: 5, now: { clock.now })
        let stale = Request.getUser(id: "stale")
        let fresh = Request.getUser(id: "fresh")

        clock.advance(by: 5)
        XCTAssertNil(limiter.validateRateLimit(for: stale))

        clock.advance(by: 6)
        XCTAssertNil(limiter.validateRateLimit(for: fresh))

        XCTAssertNil(limiter.requests[stale.hashValue], "10.1s after construction the sweep is due and drops the stale bucket")
        XCTAssertNotNil(limiter.requests[fresh.hashValue], "the bucket recorded by this very call stays")
    }

    func testTheGlobalPruneDoesNotRunInsideTheGuardWindow() {
        let clock = RateLimiterFrozenClock(now: 1_000)
        let limiter = RateLimiter(maxRequestsPerSecond: 5, now: { clock.now })
        let stale = Request.getUser(id: "stale")
        let fresh = Request.getUser(id: "fresh")

        XCTAssertNil(limiter.validateRateLimit(for: stale))

        // The stale bucket is long outside the 1s rate window, but the global
        // sweep is not due yet.
        clock.advance(by: 9.9)
        XCTAssertNil(limiter.validateRateLimit(for: fresh))

        XCTAssertNotNil(limiter.requests[stale.hashValue], "the sweep must not run before the 10s guard elapses")
    }

    func testWindowExpiryAllowsSameRequestAgain() async throws {
        let limiter = RateLimiter(maxRequestsPerSecond: 1)
        let request = Request.getUser(id: "user1")

        XCTAssertNil(limiter.validateRateLimit(for: request))
        XCTAssertEqual(limiter.validateRateLimit(for: request)?.type, .rateLimitExceeded)

        // Timestamps older than 1 second are dropped from the sliding window.
        try await Task.sleep(nanoseconds: 1_100_000_000)

        XCTAssertNil(limiter.validateRateLimit(for: request))
    }
}


/// Counts the requests the limiter let through, per key.
// @unchecked: the dictionary is lock-guarded.
private final class RateLimiterAllowanceCounter: @unchecked Sendable {

    private let lock = NSLock()
    private var allowed: [String: Int] = [:]

    func record(_ key: String) {
        lock.lock()
        allowed[key, default: 0] += 1
        lock.unlock()
    }

    func counts() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return allowed
    }
}


/// A clock the test moves by hand, so the sliding window is deterministic.
// @unchecked: `current` is only advanced from the test's own serial flow.
private final class RateLimiterFrozenClock: @unchecked Sendable {

    private var current: TimeInterval

    init(now: TimeInterval) {
        self.current = now
    }

    var now: TimeInterval {
        return current
    }

    func advance(by interval: TimeInterval) {
        current += interval
    }
}
