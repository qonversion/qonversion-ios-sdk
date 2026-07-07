//
//  RequestsStorageTests.swift
//  QonversionUnitTests
//
//  The storage persists failed retriable requests as codable StoredRequest
//  values (URLRequest itself is not plist-compatible), capped to protect
//  UserDefaults from unbounded growth (TDD — written before the implementation).
//

import XCTest
@testable import Qonversion

final class RequestsStorageTests: XCTestCase {

    private let storeKey = "io.qonversion.sdk.storage.requests"

    private func makeStorage(_ defaults: UserDefaults) -> RequestsStorage {
        RequestsStorage(userDefaults: defaults, storeKey: storeKey)
    }

    private func makeRequest(url: String = "https://api.qonversion.io/v3/users/u/purchases", body: Data? = Data("{\"price\": \"9.99\"}".utf8)) -> StoredRequest {
        StoredRequest(url: url, method: "POST", body: body)
    }

    func testFetchRequestsOnEmptyStorageReturnsEmptyArray() {
        let storage = makeStorage(TestDefaults.makeIsolated())

        XCTAssertEqual(storage.fetchRequests(), [])
    }

    func testAppendedRequestSurvivesTheRoundTrip() {
        let defaults = TestDefaults.makeIsolated()
        let storage = makeStorage(defaults)

        storage.append(makeRequest())

        // A fresh storage over the same defaults reads the persisted request.
        let fetched = makeStorage(defaults).fetchRequests()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.url, "https://api.qonversion.io/v3/users/u/purchases")
        XCTAssertEqual(fetched.first?.method, "POST")
        XCTAssertEqual(fetched.first?.body, Data("{\"price\": \"9.99\"}".utf8))
    }

    func testAppendKeepsOrder() {
        let storage = makeStorage(TestDefaults.makeIsolated())

        storage.append(makeRequest(url: "https://a"))
        storage.append(makeRequest(url: "https://b"))

        XCTAssertEqual(storage.fetchRequests().map(\.url), ["https://a", "https://b"])
    }

    func testAppendDropsOldestBeyondTheCap() {
        let storage = makeStorage(TestDefaults.makeIsolated())

        for index in 0..<(RequestsStorage.maxStoredRequests + 5) {
            storage.append(makeRequest(url: "https://request-\(index)"))
        }

        let fetched = storage.fetchRequests()
        XCTAssertEqual(fetched.count, RequestsStorage.maxStoredRequests)
        XCTAssertEqual(fetched.first?.url, "https://request-5", "the oldest requests are dropped first")
        XCTAssertEqual(fetched.last?.url, "https://request-\(RequestsStorage.maxStoredRequests + 4)")
    }

    func testCleanRemovesEverything() {
        let defaults = TestDefaults.makeIsolated()
        let storage = makeStorage(defaults)
        storage.append(makeRequest())

        storage.clean()

        XCTAssertNil(defaults.object(forKey: storeKey))
        XCTAssertEqual(storage.fetchRequests(), [])
    }

    func testFetchRequestsIgnoresForeignValueUnderTheKey() {
        let defaults = TestDefaults.makeIsolated()
        defaults.set(["not", "stored", "requests"], forKey: storeKey)

        XCTAssertEqual(makeStorage(defaults).fetchRequests(), [])
    }
}
