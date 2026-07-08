//
//  RateLimiterTests.swift
//  QonversionUnitTests
//
//  Fixation tests for RateLimiter. The limiter is keyed by request.hashValue
//  and allows up to maxRequestsPerSecond identical requests per sliding 1s window.
//

import XCTest
@testable import Qonversion

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
        let requestC = Request.getProducts(userId: "user1")

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
