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
}
