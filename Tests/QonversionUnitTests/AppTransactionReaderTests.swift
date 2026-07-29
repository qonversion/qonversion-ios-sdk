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

    /// A scripted sequence of store answers; "fail" models a throwing read.
    private final class ReadOutcomes: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: [String]

        init(_ remaining: [String]) {
            self.remaining = remaining
        }

        func next() -> String? {
            lock.lock()
            defer { lock.unlock() }
            guard !remaining.isEmpty else { return nil }
            let value: String = remaining.removeFirst()

            return value == "fail" ? nil : value
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

    func testAFailedReadIsRetriedByTheNextCaller() async {
        // A throwing read is a transient store/network failure. Settling it as
        // "unknown" for the whole process means one offline launch costs the
        // install its original app version until the app is killed.
        let counter = ReadCounter()
        let reader = AppTransactionReader {
            counter.increment()
            throw MockError.stubbed
        }

        _ = await reader.originalAppVersion()
        _ = await reader.originalAppVersion()

        XCTAssertEqual(counter.value, 2)
    }

    func testAVersionReadAfterAFailedOneSettlesAndIsServedFromThereOn() async {
        let counter = ReadCounter()
        let outcomes = ReadOutcomes(["fail", "1.0.3"])
        let reader = AppTransactionReader {
            counter.increment()
            guard let version: String = outcomes.next() else { throw MockError.stubbed }
            return version
        }

        _ = await reader.originalAppVersion()
        let second = await reader.originalAppVersion()
        let third = await reader.originalAppVersion()

        XCTAssertEqual(second, "1.0.3")
        XCTAssertEqual(third, "1.0.3")
        XCTAssertEqual(counter.value, 2, "the settled answer is served without touching the store again")
    }

    func testALegitimateNilAnswerIsSettledAndNotRetried() async {
        // Below iOS 16 the store answers "there is no such value" — that is an
        // answer, not a failure, and re-reading it would be pointless.
        let counter = ReadCounter()
        let reader = AppTransactionReader { () -> String? in
            counter.increment()
            return nil
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
