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
final class RateLimiter: RateLimiterInterface {
    private let maxRequestsPerSecond: UInt
    private let lock = NSLock()
    private var requests: [Int: [TimeInterval]] = [:]

    init(maxRequestsPerSecond: UInt) {
        self.maxRequestsPerSecond = maxRequestsPerSecond
    }

    func validateRateLimit(for request: Request) -> NoCodesError? {
        let hash: Int = request.hashValue

        lock.lock()
        defer { lock.unlock() }

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
        let timestamp: TimeInterval = Date().timeIntervalSince1970

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

        let timestamp: TimeInterval = Date().timeIntervalSince1970
        var filteredRequestTimestamps: [TimeInterval] = []
        for requestTimestamp in requestTimestamps.reversed() {
            if timestamp - requestTimestamp < 1 /* sec */ {
                filteredRequestTimestamps.insert(requestTimestamp, at: 0)
            } else {
                break
            }
        }

        requests[hash] = filteredRequestTimestamps
    }
}
