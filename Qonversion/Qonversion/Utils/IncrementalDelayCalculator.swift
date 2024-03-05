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
        var delay: Float = Float(minDelay) + pow(Constants.factor.rawValue, Float(retriesCount))
        var delta = Int((delay * Constants.jitter.rawValue).rounded())

        delay += Float(Int.random(in: 0...delta))
        let resultDelay = Int(min(delay.rounded(), Constants.maxDelay.rawValue))

        return resultDelay
    }
}
