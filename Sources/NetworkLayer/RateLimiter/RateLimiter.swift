//
//  RateLimiter.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 08.02.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//
import Foundation

// @unchecked: the requests map is lock-guarded.
final class RateLimiter: RateLimiterInterface, @unchecked Sendable {
    private var maxRequestsPerSecond: UInt
    private(set) var requests: [Int: [TimeInterval]] = [:]
    /// Anchored at construction, not at zero: a zero anchor makes the first
    /// call of the process due for a sweep and re-anchors the window there.
    private var lastGlobalPrune: TimeInterval

    // Concurrent requests validate simultaneously; the check-then-save below
    // is a read-modify-write over the shared map.
    private let lock = NSLock()

    /// `now` is injectable so the sliding window can be pinned deterministically
    /// in tests: asserting "exactly N admissions" against the wall clock turns
    /// into a race the moment the machine is loaded and the batch straddles a
    /// window boundary.
    private let now: @Sendable () -> TimeInterval

    init(maxRequestsPerSecond: UInt, now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.maxRequestsPerSecond = maxRequestsPerSecond
        self.now = now
        self.lastGlobalPrune = now()
    }

    func validateRateLimit(for request: Request) -> QonversionError? {
        lock.lock()
        defer { lock.unlock() }

        pruneStaleBucketsIfNeeded()

        let hash: Int = request.hashValue
        let isLimitExceeded: Bool = isRateLimitExceeded(hash: hash)
        if isLimitExceeded {
            let error = QonversionError(type: .rateLimitExceeded, message: "Rate limit exceeded for the current request", error: nil, additionalInfo: nil)
            return error
        } else {
            saveRequest(hash: hash)
            return nil
        }
    }
}

// MARK: - Private

extension RateLimiter {
    
    private func saveRequest(hash: Int) {
        let timestamp: TimeInterval = now()

        if requests[hash] == nil {
            requests[hash] = []
        }

        requests[hash]?.append(timestamp)
    }

    func isRateLimitExceeded(hash: Int) -> Bool {
        removeOutdatedRequests(hash: hash)

        guard let requestsPerType: [TimeInterval] = requests[hash] else { return false }

        return requestsPerType.count >= maxRequestsPerSecond
    }

    private func removeOutdatedRequests(hash: Int) {
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

        // An empty bucket must not survive: every distinct body hash mints a
        // new key, and keeping them would grow the map without bound.
        requests[hash] = filteredRequestTimestamps.isEmpty ? nil : filteredRequestTimestamps
    }

    /// Drops buckets whose newest entry is already outside the 1-second
    /// window. Runs at most once per 10 seconds — the map stays bounded by
    /// the actual request rate instead of the request history.
    private func pruneStaleBucketsIfNeeded() {
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
