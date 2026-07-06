//
//  IncrementalDelayCalculatorTests.swift
//  QonversionUnitTests
//
//  Fixation tests for IncrementalDelayCalculator.
//
//  Formula (from source): delay = minDelay + 2.4^retriesCount,
//  delta = Int((delay * 0.4).rounded()), delay += random(0...delta),
//  result = Int(min(delay.rounded(), 1000)).
//

import XCTest
@testable import Qonversion

final class IncrementalDelayCalculatorTests: XCTestCase {

    private let calculator = IncrementalDelayCalculator()

    private func bounds(minDelay: Int, retriesCount: Int) -> ClosedRange<Int> {
        let base = Float(minDelay) + pow(2.4, Float(retriesCount))
        let delta = Int((base * 0.4).rounded())
        let lower = Int(min(base.rounded(), 1000))
        let upper = Int(min((base + Float(delta)).rounded(), 1000))
        return lower...upper
    }

    func testResultIsWithinFormulaBounds() {
        for _ in 0..<100 {
            let result = calculator.countDelay(minDelay: 5, retriesCount: 3)
            // base = 5 + 2.4^3 = 18.824; delta = 8; result in [19, 27]
            XCTAssertTrue(bounds(minDelay: 5, retriesCount: 3).contains(result), "Got \(result)")
            XCTAssertGreaterThanOrEqual(result, 5, "Result must not be below minDelay")
        }
    }

    func testResultIsAtLeastMinDelayPlusExponentialBase() {
        for retries in 0...5 {
            let result = calculator.countDelay(minDelay: 10, retriesCount: retries)
            let lowerBound = Int((Float(10) + pow(2.4, Float(retries))).rounded(.down))
            XCTAssertGreaterThanOrEqual(result, lowerBound)
        }
    }

    func testDelayGrowsWithRetriesCount() {
        // Deterministic bound comparison (no flaky equality):
        // retries=1: max possible = round(1 + 2.4 + delta(=1)) = 4
        // retries=6: min possible = round(1 + 2.4^6) = 192
        for _ in 0..<50 {
            let small = calculator.countDelay(minDelay: 1, retriesCount: 1)
            let large = calculator.countDelay(minDelay: 1, retriesCount: 6)
            XCTAssertLessThanOrEqual(small, 4)
            XCTAssertGreaterThanOrEqual(large, 192)
            XCTAssertGreaterThan(large, small)
        }
    }

    func testResultIsCappedAtMaxDelay() {
        // base = 100 + 2.4^9 ≈ 2742 — always above the 1000 cap.
        for _ in 0..<20 {
            XCTAssertEqual(calculator.countDelay(minDelay: 100, retriesCount: 9), 1000)
        }
    }

    func testCapAppliesEvenWhenMinDelayExceedsMaxDelay() {
        // Fixates current behavior: the 1000 cap wins over minDelay, so a caller
        // asking for a minimum of 2000 still gets exactly 1000 back.
        XCTAssertEqual(calculator.countDelay(minDelay: 2000, retriesCount: 1), 1000)
    }

    func testZeroInputsProduceDeterministicMinimum() {
        // base = 0 + 2.4^0 = 1; delta = Int(0.4.rounded()) = 0; random(0...0) = 0.
        XCTAssertEqual(calculator.countDelay(minDelay: 0, retriesCount: 0), 1)
    }
}
