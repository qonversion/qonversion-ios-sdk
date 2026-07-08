//
//  IncrementalDelayCalculator.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 27.02.2024.
//

import Foundation

fileprivate enum Constants: Float {
    case jitter = 0.4
    case factor = 2.4
    case maxDelay = 1000
}

internal class IncrementalDelayCalculator {
    func countDelay(minDelay: Int, retriesCount: Int) -> Int {
        // Clamp before deriving the jitter: pow overflows Float to infinity
        // at large retry counts, and Int(infinity) traps.
        var delay: Float = min(Float(minDelay) + pow(Constants.factor.rawValue, Float(retriesCount)), Constants.maxDelay.rawValue)
        let delta = Int((delay * Constants.jitter.rawValue).rounded())

        delay += Float(Int.random(in: 0...delta))
        let resultDelay = Int(min(delay.rounded(), Constants.maxDelay.rawValue))

        return resultDelay
    }
}
