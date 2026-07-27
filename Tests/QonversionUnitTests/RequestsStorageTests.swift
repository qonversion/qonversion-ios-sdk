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

    private func makeRequest(url: String = "https://api.qonversion.io/v3/users/u/purchases", body: Data? = Data("{\"price\": \"9.99\"}".utf8), dedupKey: String? = nil) -> StoredRequest {
        StoredRequest(url: url, method: "POST", body: body, dedupKey: dedupKey)
    }

    // MARK: - atomic replace

    func testReplaceSwapsTheQueuedRequestInPlace() {
        let storage = makeStorage(TestDefaults.makeIsolated())
        let original: StoredRequest = makeRequest()
        storage.append(original)
        let bumped = StoredRequest(url: original.url, method: original.method, body: original.body, dedupKey: original.dedupKey, trigger: original.trigger, attempt: 2)

        storage.replace(original, with: bumped, ifGenerationIs: storage.cleanGeneration)

        XCTAssertEqual(storage.fetchRequests().map(\.attempt), [2])
    }

    func testReplaceIsANoOpAfterTheQueueWasCleaned() {
        // The whole point of the atomic form. An empty queue after clean()
        // would make the guard untestable — replace finds nothing to swap
        // either way — so the NEW user enqueues an identical request and the
        // stale generation must not be allowed to touch it.
        let storage = makeStorage(TestDefaults.makeIsolated())
        let original: StoredRequest = makeRequest()
        storage.append(original)
        let generation: Int = storage.cleanGeneration
        storage.clean()
        storage.append(makeRequest())
        let bumped = StoredRequest(url: original.url, method: original.method, body: original.body, dedupKey: original.dedupKey, trigger: original.trigger, attempt: 2)

        storage.replace(original, with: bumped, ifGenerationIs: generation)

        XCTAssertEqual(storage.fetchRequests().map(\.attempt), [1],
                       "the new user's identical entry must not inherit the previous user's attempt count")
    }

    // MARK: - generation-guarded append

    func testAppendIsANoOpAgainstAStaleGeneration() {
        // A request that failed after the queue was cleaned belongs to the
        // previous user; re-queueing it would replay it under the new uid.
        let storage = makeStorage(TestDefaults.makeIsolated())
        let generation: Int = storage.cleanGeneration
        storage.clean()

        storage.append(makeRequest(), ifGenerationIs: generation)

        XCTAssertTrue(storage.fetchRequests().isEmpty, "a cleaned queue must stay clean")
    }

    func testAppendAgainstTheCurrentGenerationStillEnqueues() {
        let storage = makeStorage(TestDefaults.makeIsolated())
        storage.clean()

        storage.append(makeRequest(), ifGenerationIs: storage.cleanGeneration)

        XCTAssertEqual(storage.fetchRequests().count, 1, "a new request must still be queued after a switch")
    }

    func testRemoveAllWherePersistsTheFilteredQueue() {
        let storage = makeStorage(TestDefaults.makeIsolated())
        storage.append(StoredRequest(url: "https://a", method: "POST", body: nil, dedupKey: "createPurchase-u1-tx1"))
        storage.append(StoredRequest(url: "https://b", method: "POST", body: nil, dedupKey: "createPurchase-u2-tx2"))

        storage.removeAll { $0.dedupKey?.hasSuffix("-tx1") == true }

        let remaining: [String?] = storage.fetchRequests().map { $0.dedupKey }
        XCTAssertEqual(remaining, ["createPurchase-u2-tx2"])
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

    func testAppendSkipsDuplicateDedupKey() {
        // The same purchase failing twice must not queue twice.
        let storage = makeStorage(TestDefaults.makeIsolated())

        storage.append(makeRequest(dedupKey: "createPurchase-u-t1"))
        storage.append(makeRequest(body: Data("{\"other\": true}".utf8), dedupKey: "createPurchase-u-t1"))
        storage.append(makeRequest(dedupKey: "createPurchase-u-t2"))

        XCTAssertEqual(storage.fetchRequests().compactMap(\.dedupKey), ["createPurchase-u-t1", "createPurchase-u-t2"])
    }

    func testAppendWithoutDedupKeyIsNeverDeduplicated() {
        let storage = makeStorage(TestDefaults.makeIsolated())

        storage.append(makeRequest())
        storage.append(makeRequest())

        XCTAssertEqual(storage.fetchRequests().count, 2)
    }

    func testRemoveDeletesTheGivenRequestOnly() {
        let storage = makeStorage(TestDefaults.makeIsolated())
        let first = makeRequest(url: "https://a", dedupKey: "k1")
        let second = makeRequest(url: "https://b", dedupKey: "k2")
        storage.append(first)
        storage.append(second)

        storage.remove(first)

        XCTAssertEqual(storage.fetchRequests().map(\.url), ["https://b"])
    }

    func testCleanRemovesEverything() {
        let defaults = TestDefaults.makeIsolated()
        let storage = makeStorage(defaults)
        storage.append(makeRequest())

        storage.clean()

        XCTAssertNil(defaults.object(forKey: storeKey))
        XCTAssertEqual(storage.fetchRequests(), [])
    }

    func testQueuesOfDifferentApiKeysAreIsolated() {
        // Switching projects (staging <-> prod key) must not replay the other
        // project's queue with the new Authorization.
        let defaults = TestDefaults.makeIsolated()
        let first = MiscAssembly(apiKey: "key_A", userDefaults: defaults, internalConfig: InternalConfig(userId: "")).requestsStorage()
        let second = MiscAssembly(apiKey: "key_B", userDefaults: defaults, internalConfig: InternalConfig(userId: "")).requestsStorage()

        first.append(StoredRequest(url: "https://a", method: "POST", body: nil, dedupKey: nil))

        XCTAssertEqual(first.fetchRequests().count, 1)
        XCTAssertTrue(second.fetchRequests().isEmpty)
    }

    func testConcurrentAppendsDoNotLoseRequests() async {
        // Below the cap on purpose: at 100 appends into a 50-slot queue the
        // count would land on the cap even if half the updates were lost, so
        // the assertion proved nothing. Every single request must be there.
        let storage = makeStorage(TestDefaults.makeIsolated())
        let count: Int = RequestsStorage.maxStoredRequests - 10

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                group.addTask {
                    storage.append(StoredRequest(url: "https://request-\(index)", method: "POST", body: nil, dedupKey: "k\(index)"))
                }
            }
        }

        let stored: Set<String> = Set(storage.fetchRequests().compactMap { $0.dedupKey })
        let expected: Set<String> = Set((0..<count).map { "k\($0)" })
        XCTAssertEqual(stored, expected, "the read-modify-write must be atomic: no lost updates")
    }

    func testConcurrentAppendsBeyondTheCapTrimToTheCap() async {
        let storage = makeStorage(TestDefaults.makeIsolated())

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<(RequestsStorage.maxStoredRequests * 2) {
                group.addTask {
                    storage.append(StoredRequest(url: "https://request-\(index)", method: "POST", body: nil, dedupKey: "k\(index)"))
                }
            }
        }

        XCTAssertEqual(storage.fetchRequests().count, RequestsStorage.maxStoredRequests,
                       "the cap is the only thing that may drop a request")
    }

    func testFetchRequestsIgnoresForeignValueUnderTheKey() {
        let defaults = TestDefaults.makeIsolated()
        defaults.set(["not", "stored", "requests"], forKey: storeKey)

        XCTAssertEqual(makeStorage(defaults).fetchRequests(), [])
    }
}

// MARK: - legacy offline purchase queue

final class LegacyPurchasesQueueMigrationTests: XCTestCase {

    private let suiteName = "qonversion.localstorage.main"
    private let queueKey = "com.qonversion.keys.requests.stored.purchases"
    private var legacyDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        legacyDefaults = UserDefaults(suiteName: suiteName)
        legacyDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        legacyDefaults.removePersistentDomain(forName: suiteName)
        legacyDefaults = nil
        super.tearDown()
    }

    func testTheLegacyPurchaseQueueIsConsumed() {
        // The archived payloads target the previous API and cannot be
        // replayed; the unfinished-transaction sweep re-reports the purchases,
        // so the key is dropped instead of migrated.
        legacyDefaults.set(Data([0x01, 0x02]), forKey: queueKey)
        let migration = LegacyPurchasesQueueMigration()

        migration.run()

        XCTAssertNil(legacyDefaults.data(forKey: queueKey))
    }

    func testRunningTwiceIsHarmless() {
        let migration = LegacyPurchasesQueueMigration()

        migration.run()
        migration.run()

        XCTAssertNil(legacyDefaults.data(forKey: queueKey))
    }
}
