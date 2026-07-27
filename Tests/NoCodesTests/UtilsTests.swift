//
//  UtilsTests.swift
//  NoCodesTests
//
//  The currency symbol fallback and its memoization.
//

import XCTest
@testable import NoCodes

final class UtilsTests: XCTestCase {

    func testKnownCurrencyCodesResolveToASymbol() {
        XCTAssertEqual("USD".toCurrencySymbol(), "$")
        XCTAssertNotNil("EUR".toCurrencySymbol())
    }

    func testUnknownCurrencyCodesResolveToNothing() {
        XCTAssertNil("NOT_A_CURRENCY".toCurrencySymbol())
    }

    func testRepeatedResolutionsAreStableAndMemoized() {
        // The first call scans every available locale; the memoized answers
        // must match it, including the cached "no symbol" one.
        let firstSymbol: String? = "USD".toCurrencySymbol()
        let secondSymbol: String? = "USD".toCurrencySymbol()
        let firstMiss: String? = "NOT_A_CURRENCY".toCurrencySymbol()
        let secondMiss: String? = "NOT_A_CURRENCY".toCurrencySymbol()

        XCTAssertEqual(firstSymbol, secondSymbol)
        XCTAssertNil(firstMiss)
        XCTAssertNil(secondMiss)
    }

    func testConcurrentResolutionsAgreeOnTheSameSymbol() {
        let symbols = NSMutableArray()
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let symbol: String? = "USD".toCurrencySymbol()

            lock.lock()
            symbols.add(symbol ?? "")
            lock.unlock()
        }

        let distinct: Set<String> = Set(symbols.compactMap { $0 as? String })
        XCTAssertEqual(distinct.count, 1)
    }
}
