//
//  AppTransactionReaderTests.swift
//  QonversionUnitTests
//
//  Contract tests for the original app version seam: the store is read once
//  per process, and no store failure ever reaches the caller.
//

import XCTest
@testable import Qonversion

final class AppTransactionReaderTests: XCTestCase {

    /// Counts the store reads a reader performs.
    private final class ReadCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    func testAnswersTheVersionTheStoreReports() async {
        let reader = AppTransactionReader { "1.0.3" }

        let version = await reader.originalAppVersion()

        XCTAssertEqual(version, "1.0.3")
    }

    func testAStoreFailureBecomesNilInsteadOfThrowing() async {
        let reader = AppTransactionReader { throw MockError.stubbed }

        let version = await reader.originalAppVersion()

        XCTAssertNil(version)
    }

    func testTheStoreIsReadOnlyOnce() async {
        let counter = ReadCounter()
        let reader = AppTransactionReader {
            counter.increment()
            return "1.0.3"
        }

        _ = await reader.originalAppVersion()
        _ = await reader.originalAppVersion()
        let third = await reader.originalAppVersion()

        XCTAssertEqual(third, "1.0.3")
        XCTAssertEqual(counter.value, 1)
    }

    func testAFailedReadIsNotRetried() async {
        // The version is informational: retrying on every user request would
        // spend a store round trip per call for a field nobody blocks on.
        let counter = ReadCounter()
        let reader = AppTransactionReader {
            counter.increment()
            throw MockError.stubbed
        }

        _ = await reader.originalAppVersion()
        _ = await reader.originalAppVersion()

        XCTAssertEqual(counter.value, 1)
    }

    func testConcurrentCallersShareOneRead() async {
        let counter = ReadCounter()
        let reader = AppTransactionReader {
            counter.increment()
            try await Task.sleep(nanoseconds: 50_000_000)
            return "1.0.3"
        }

        async let first = reader.originalAppVersion()
        async let second = reader.originalAppVersion()
        async let third = reader.originalAppVersion()

        let versions = await [first, second, third]

        XCTAssertEqual(versions, ["1.0.3", "1.0.3", "1.0.3"])
        XCTAssertEqual(counter.value, 1)
    }
}
