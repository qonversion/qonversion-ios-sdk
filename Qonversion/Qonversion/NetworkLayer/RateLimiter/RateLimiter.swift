//
//  RateLimiter.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 08.02.2024.
//  Copyright © 2024 Qonversion Inc. All rights reserved.
//
import Foundation

final class RateLimiter {
    private var maxRequestsPerSecond: UInt
    private var requests: [Int: [TimeInterval]] = [:]

    init(maxRequestsPerSecond: UInt) {
        self.maxRequestsPerSecond = maxRequestsPerSecond
    }

    func validateRateLimit(request: Request) -> QonversionError? {
        let hash: Int = request.hashValue
        if isRateLimitExceeded(hash: hash) {
            let error = QonversionError(type: .rateLimitExceeded, message: "Rate limit exceeded for the current request", error: nil, additionalInfo: nil)
            return error
        } else {
            saveRequest(hash: hash)
            return nil
        }
    }

    func saveRequest(hash: Int) {
        let timestamp: TimeInterval = Date().timeIntervalSince1970

        if requests[hash] == nil {
            requests[hash] = []
        }

        requests[hash]?.append(timestamp)
    }

    func isRateLimitExceeded(hash: Int) -> Bool {
        removeOutdatedRequests(hash: hash)

        guard let requestsPerType = requests[hash] else {
            return false
        }

        return requestsPerType.count >= maxRequestsPerSecond
    }

    private func removeOutdatedRequests(hash: Int) {
        guard let requestTimestamps: [TimeInterval] = requests[hash] else {
            return
        }

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
