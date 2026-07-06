//
//  RequestsStorageTests.swift
//  QonversionUnitTests
//
//  Fixation tests for the real RequestsStorage over an isolated UserDefaults suite.
//
//  IMPORTANT CRASH TRAP (fixates current behavior): store(requests:) and
//  append(requests:) write [URLRequest] directly into UserDefaults via
//  userDefaults.set(_:forKey:). URLRequest is NOT a property-list type, so calling
//  either method with a non-empty [URLRequest] raises NSInvalidArgumentException
//  ("Attempt to insert non-property list object") and CRASHES the process.
//  That crash cannot be caught from Swift tests, so these tests deliberately never
//  put a real URLRequest into the real storage — only the empty-array and clean()
//  paths are exercised here.
//

import XCTest
@testable import Qonversion

final class RequestsStorageTests: XCTestCase {

    private let storeKey = "io.qonversion.sdk.storage.requests"

    func testFetchRequestsOnEmptyStorageReturnsEmptyArray() {
        let defaults = TestDefaults.makeIsolated()
        let storage = RequestsStorage(userDefaults: defaults, storeKey: storeKey)

        XCTAssertEqual(storage.fetchRequests(), [])
    }

    func testStoreEmptyArrayWritesValueAndFetchReturnsEmpty() {
        let defaults = TestDefaults.makeIsolated()
        let storage = RequestsStorage(userDefaults: defaults, storeKey: storeKey)

        // An empty array IS plist-compatible, so this specific call survives.
        storage.store(requests: [])

        XCTAssertNotNil(defaults.object(forKey: storeKey))
        XCTAssertEqual(storage.fetchRequests(), [])
    }

    func testAppendEmptyArrayKeepsStorageEmpty() {
        let defaults = TestDefaults.makeIsolated()
        let storage = RequestsStorage(userDefaults: defaults, storeKey: storeKey)

        storage.append(requests: [])

        XCTAssertEqual(storage.fetchRequests(), [])
    }

    func testCleanRemovesTheKey() {
        let defaults = TestDefaults.makeIsolated()
        let storage = RequestsStorage(userDefaults: defaults, storeKey: storeKey)
        storage.store(requests: [])
        XCTAssertNotNil(defaults.object(forKey: storeKey))

        storage.clean()

        XCTAssertNil(defaults.object(forKey: storeKey))
        XCTAssertEqual(storage.fetchRequests(), [])
    }

    func testFetchRequestsIgnoresForeignValueUnderTheKey() {
        // Fixates current behavior: a non-[URLRequest] value under the key is silently
        // treated as an empty storage (the as? cast fails and falls back to []).
        let defaults = TestDefaults.makeIsolated()
        defaults.set(["not", "url", "requests"], forKey: storeKey)
        let storage = RequestsStorage(userDefaults: defaults, storeKey: storeKey)

        XCTAssertEqual(storage.fetchRequests(), [])
    }
}
