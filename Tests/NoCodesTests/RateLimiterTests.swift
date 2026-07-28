//
//  RateLimiterTests.swift
//  NoCodesTests
//

import XCTest
@testable import NoCodes

final class RateLimiterTests: XCTestCase {

    func testAllowsExactlyTheConfiguredNumberOfRequestsPerSecond() {
        let limiter = RateLimiter(maxRequestsPerSecond: 5)
        let request = Request.getScreen(id: "screen-1")

        let allowed: Int = (0..<20).filter { _ in limiter.validateRateLimit(for: request) == nil }.count

        XCTAssertEqual(allowed, 5)
    }

    func testConcurrentValidationKeepsTheLimitExact() {
        let limiter = RateLimiter(maxRequestsPerSecond: 5)
        let request = Request.getScreen(id: "screen-concurrent")
        let counterLock = NSLock()
        var allowed = 0

        DispatchQueue.concurrentPerform(iterations: 500) { _ in
            guard limiter.validateRateLimit(for: request) == nil else { return }

            counterLock.lock()
            allowed += 1
            counterLock.unlock()
        }

        // Without a lock inside the limiter this both races the dictionary and
        // lets more than the configured number of requests through.
        XCTAssertEqual(allowed, 5)
    }

    func testDifferentRequestsAreLimitedIndependently() {
        let limiter = RateLimiter(maxRequestsPerSecond: 5)
        let first = Request.getScreen(id: "screen-a")
        let second = Request.getScreenByContextKey(contextKey: "main")

        let allowedFirst: Int = (0..<10).filter { _ in limiter.validateRateLimit(for: first) == nil }.count
        let allowedSecond: Int = (0..<10).filter { _ in limiter.validateRateLimit(for: second) == nil }.count

        XCTAssertEqual(allowedFirst, 5)
        XCTAssertEqual(allowedSecond, 5)
    }

    // MARK: - Bucket lifetime

    /// Every screen id and context key mints its own bucket. A bucket that
    /// fell out of the window must go, not stay behind as an empty array under
    /// a key nothing will ever visit again.
    func testABucketThatFellOutOfTheWindowIsDropped() {
        let clock = RateLimiterFrozenClock(now: 1_000)
        let limiter = RateLimiter(maxRequestsPerSecond: 5, now: { clock.now })
        let stale = Request.getScreen(id: "screen-stale")
        let fresh = Request.getScreen(id: "screen-fresh")

        XCTAssertNil(limiter.validateRateLimit(for: stale))

        clock.advance(by: 11)
        XCTAssertNil(limiter.validateRateLimit(for: fresh))

        XCTAssertNil(limiter.requests[stale.hashValue], "the sweep is due and the stale bucket is gone")
        XCTAssertNotNil(limiter.requests[fresh.hashValue], "the bucket recorded by this very call stays")
    }

    /// The sweep must stay off the hot path: once it has run, the next ten
    /// seconds of calls must not walk the whole map again.
    func testTheSweepIsGatedByItsGuardWindow() {
        let clock = RateLimiterFrozenClock(now: 1_000)
        let limiter = RateLimiter(maxRequestsPerSecond: 5, now: { clock.now })
        let stale = Request.getScreen(id: "screen-stale")
        let fresh = Request.getScreen(id: "screen-fresh")

        clock.advance(by: 11)
        XCTAssertNil(limiter.validateRateLimit(for: stale))

        clock.advance(by: 5)
        XCTAssertNil(limiter.validateRateLimit(for: fresh))

        XCTAssertNotNil(limiter.requests[stale.hashValue], "the guard has not elapsed since the last sweep")
    }

    /// A backward clock jump (NTP, a manual date change) must re-anchor the
    /// guard instead of disabling the sweep for good.
    func testABackwardClockJumpReAnchorsTheSweepGuard() {
        let clock = RateLimiterFrozenClock(now: 1_000)
        let limiter = RateLimiter(maxRequestsPerSecond: 5, now: { clock.now })
        let stale = Request.getScreen(id: "screen-stale")
        let fresh = Request.getScreen(id: "screen-fresh")

        clock.advance(by: -86_400)
        XCTAssertNil(limiter.validateRateLimit(for: stale))

        clock.advance(by: 11)
        XCTAssertNil(limiter.validateRateLimit(for: fresh))

        XCTAssertNil(limiter.requests[stale.hashValue])
        XCTAssertNotNil(limiter.requests[fresh.hashValue])
    }

    /// The window is a sliding one: a second of quiet buys a full new allowance.
    func testTheAllowanceComesBackAfterTheWindowPasses() {
        let clock = RateLimiterFrozenClock(now: 1_000)
        let limiter = RateLimiter(maxRequestsPerSecond: 2, now: { clock.now })
        let request = Request.getScreen(id: "screen-a")

        XCTAssertNil(limiter.validateRateLimit(for: request))
        XCTAssertNil(limiter.validateRateLimit(for: request))
        XCTAssertNotNil(limiter.validateRateLimit(for: request))

        clock.advance(by: 2)

        XCTAssertNil(limiter.validateRateLimit(for: request))
    }
}

private final class RateLimiterFrozenClock: @unchecked Sendable {

    private var current: TimeInterval

    init(now: TimeInterval) {
        current = now
    }

    var now: TimeInterval {
        return current
    }

    func advance(by interval: TimeInterval) {
        current += interval
    }
}
