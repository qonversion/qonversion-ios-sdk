//
//  RateLimiter.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 08.02.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//
import Foundation

// The limiter is consulted from every request task, so the timestamp table is
// shared mutable state. The lock is only ever held around synchronous
// dictionary work — never across a suspension point.
// @unchecked: the only mutable state is `requests`, guarded by `lock` on
// every access.
final class RateLimiter: RateLimiterInterface, @unchecked Sendable {
    private let maxRequestsPerSecond: UInt
    private let lock = NSLock()
    private(set) var requests: [Int: [TimeInterval]] = [:]
    // Anchored at construction, not at zero: a zero anchor makes the first call
    // of the process due for a sweep and re-anchors the window there.
    private var lastGlobalPrune: TimeInterval

    // Injectable so the sliding window can be pinned in tests, where asserting
    // an exact allowance against the wall clock is a race.
    private let now: @Sendable () -> TimeInterval

    init(maxRequestsPerSecond: UInt, now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.maxRequestsPerSecond = maxRequestsPerSecond
        self.now = now
        self.lastGlobalPrune = now()
    }

    func validateRateLimit(for request: Request) -> NoCodesError? {
        let hash: Int = request.hashValue

        lock.lock()
        defer { lock.unlock() }

        pruneStaleBucketsIfNeededLocked()

        let isLimitExceeded: Bool = isRateLimitExceededLocked(hash: hash)
        if isLimitExceeded {
            let error = NoCodesError(type: .rateLimitExceeded, message: "Rate limit exceeded for the current request", error: nil, additionalInfo: nil)
            return error
        } else {
            saveRequestLocked(hash: hash)
            return nil
        }
    }
}

// MARK: - Private

extension RateLimiter {

    // All the helpers below assume the caller already holds `lock`.

    private func saveRequestLocked(hash: Int) {
        let timestamp: TimeInterval = now()

        if requests[hash] == nil {
            requests[hash] = []
        }

        requests[hash]?.append(timestamp)
    }

    private func isRateLimitExceededLocked(hash: Int) -> Bool {
        removeOutdatedRequestsLocked(hash: hash)

        guard let requestsPerType: [TimeInterval] = requests[hash] else { return false }

        return requestsPerType.count >= maxRequestsPerSecond
    }

    private func removeOutdatedRequestsLocked(hash: Int) {
        guard let requestTimestamps: [TimeInterval] = requests[hash] else { return }

        let timestamp: TimeInterval = now()
        var filteredRequestTimestamps: [TimeInterval] = []
        for requestTimestamp in requestTimestamps.reversed() {
            if timestamp - requestTimestamp < 1 /* sec */ {
                filteredRequestTimestamps.insert(requestTimestamp, at: 0)
            } else {
                break
            }
        }

        // An emptied bucket must not survive: nothing visits the key of a
        // screen that is never shown again, so it would sit there forever.
        requests[hash] = filteredRequestTimestamps.isEmpty ? nil : filteredRequestTimestamps
    }

    /// Drops buckets whose newest entry is already outside the 1-second window.
    /// Runs at most once per 10 seconds — the map then follows the current
    /// request rate instead of the whole request history.
    private func pruneStaleBucketsIfNeededLocked() {
        let currentTime: TimeInterval = now()

        // A wall clock can move backward (NTP, a manual date change); past the
        // anchor the difference below would stay negative and never sweep again.
        if currentTime < lastGlobalPrune {
            lastGlobalPrune = currentTime
        }

        guard currentTime - lastGlobalPrune > 10 else { return }
        lastGlobalPrune = currentTime

        for (hash, timestamps) in requests {
            if (timestamps.last ?? 0) < currentTime - 1 {
                requests[hash] = nil
            }
        }
    }
}
