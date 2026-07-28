//
//  IntegrationTests.swift
//  QonversionUnitTests
//
//  Object-graph integration: the REAL assembly, managers, services and
//  network layer run together; only the two process boundaries are stubbed —
//  HTTP (StubNetworkProvider answers by URL pattern and records the real
//  URLRequests the production code built) and the thin StoreKit wrapper.
//
//  The unit suite proves each unit against its contract; this layer proves
//  the contracts compose — exactly where the review found the real bugs.
//

import XCTest
import StoreKit
@testable import Qonversion

// MARK: - HTTP boundary stub

/// Canned responses by URL substring + method; records every real request.
/// Shared with the StoreKitTest layer, which stubs the same HTTP boundary
/// while running the REAL StoreKit over an SKTestSession.
final class StubNetworkProvider: NetworkProviderInterface, @unchecked Sendable {

    struct Rule {
        let method: String
        let pathPattern: String
        var status: Int
        var body: String
        var transportError: Error?
    }

    /// Segment-exact path matching: "*" matches one segment, counts must be
    /// equal — "/v4/users" can never swallow "/v4/users/uid/purchases".
    static func matches(pattern: String, path: String) -> Bool {
        let patternSegments: [Substring] = pattern.split(separator: "/")
        let pathSegments: [Substring] = path.split(separator: "/")
        guard patternSegments.count == pathSegments.count else { return false }
        return zip(patternSegments, pathSegments).allSatisfy { $0 == "*" || $0 == $1 }
    }

    private let lock = NSLock()
    private var rules: [Rule] = []
    private(set) var requests: [URLRequest] = []

    func stub(_ method: String, _ pathPattern: String, status: Int = 200, body: String = "{}", transportError: Error? = nil) {
        lock.lock()
        defer { lock.unlock() }
        // Re-stubbing a route replaces the previous rule.
        rules.removeAll { $0.method == method && $0.pathPattern == pathPattern }
        rules.append(Rule(method: method, pathPattern: pathPattern, status: status, body: body, transportError: transportError))
    }

    func recordedRequests(_ method: String, _ pathPattern: String) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests.filter { $0.httpMethod == method && Self.matches(pattern: pathPattern, path: $0.url?.path ?? "") }
    }

    func allRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func send(request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        requests.append(request)
        let rule: Rule? = rules.last { rule in
            request.httpMethod == rule.method && Self.matches(pattern: rule.pathPattern, path: request.url?.path ?? "")
        }
        lock.unlock()

        guard let rule else {
            throw URLError(.unsupportedURL)
        }
        if let transportError = rule.transportError {
            throw transportError
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: rule.status, httpVersion: nil, headerFields: nil)!
        return (Data(rule.body.utf8), response)
    }
}

// MARK: - The world under test

/// The full real object graph over stubbed boundaries — built the same way
/// Qonversion.initialize wires it, without touching the shared singleton.
private struct SdkWorld {
    let assembly: QonversionAssembly
    let network: StubNetworkProvider
    let storeKit: MockStoreKit2Wrapper
    let userDefaults: UserDefaults

    let userManager: UserManagerInterface
    let productsManager: ProductsManagerInterface
    let purchasesManager: PurchasesManagerInterface
    let entitlementsManager: EntitlementsManagerInterface
    let remoteConfigManager: RemoteConfigManagerInterface
    let userPropertiesManager: UserPropertiesManagerInterface

    init(userDefaults: UserDefaults, launchMode: Qonversion.LaunchMode = .analytics) {
        self.userDefaults = userDefaults
        network = StubNetworkProvider()
        storeKit = MockStoreKit2Wrapper()

        assembly = QonversionAssembly(apiKey: "integration-key", userDefaults: userDefaults, launchMode: launchMode)
        assembly.servicesAssembly.networkProviderOverride = network
        assembly.servicesAssembly.storeKitWrapperOverride = storeKit

        userManager = assembly.userManager()
        userPropertiesManager = assembly.userPropertiesManager()
        productsManager = assembly.productsManager()
        remoteConfigManager = assembly.remoteConfigManager()
        purchasesManager = assembly.purchasesManager()
        entitlementsManager = assembly.entitlementsManager()
    }

    var uid: String { userDefaults.string(forKey: "qonversion.keys.userId") ?? "" }

    func stubHappyUser() {
        network.stub("POST", "/v4/users", body: #"{"id": "\#(uid)", "created_at": "2026-07-27T10:00:00Z", "environment": "prod"}"#)
        network.stub("GET", "/v4/users/*", body: #"{"id": "\#(uid)", "created_at": "2026-07-27T10:00:00Z", "environment": "prod"}"#)
    }
}

final class IntegrationTests: XCTestCase {

    private var world: SdkWorld!

    override func setUp() {
        super.setUp()
        world = SdkWorld(userDefaults: TestDefaults.makeIsolated())
    }

    override func tearDown() {
        world = nil
        super.tearDown()
    }

    // MARK: - 1. user creation end to end

    func testUserCreationSendsTheRealV4RequestWithHeadersAndBody() async throws {
        world.stubHappyUser()

        let user = try await world.userManager.obtainUser()

        XCTAssertEqual(user.id, world.uid)
        let request = try XCTUnwrap(world.network.recordedRequests("POST", "/v4/users").first)
        XCTAssertEqual(request.url?.absoluteString, "https://api2.qonversion.io/v4/users")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer integration-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Attempt"), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Trigger"), "Init")
        let body = try XCTUnwrap(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["id"] as? String, world.uid)
        XCTAssertNil(body["environment"], "the SDK no longer signals a store environment")

        // The second demand answers from the cache — no extra request.
        _ = try await world.userManager.obtainUser()
        XCTAssertEqual(world.network.recordedRequests("POST", "/v4/users").count, 1)
    }

    // MARK: - 2. out-of-band transaction end to end (subscription management)

    func testObservedTransactionIsReportedFinishedAndEmitted() async throws {
        let subMgmt = SdkWorld(userDefaults: TestDefaults.makeIsolated(), launchMode: .subscriptionManagement)
        subMgmt.stubHappyUser()
        subMgmt.network.stub("POST", "/v4/users/*/purchases", body: #"{"object": "purchase"}"#)
        subMgmt.network.stub("GET", "/v4/users/*/entitlements", body: #"{"object": "list", "data": [{"id": "premium", "is_active": true}]}"#)
        guard let concreteManager = subMgmt.purchasesManager as? PurchasesManager else {
            return XCTFail("Unexpected manager type")
        }

        let transaction = Qonversion.Transaction(id: "tx-1", originalId: "tx-1", productId: "com.app.pro", jws: "signed-jws")
        concreteManager.transactionUpdated(transaction)

        let deadline = Date().addingTimeInterval(3)
        while subMgmt.storeKit.finishedTransactions.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let report = try XCTUnwrap(subMgmt.network.recordedRequests("POST", "/v4/users/*/purchases").first)
        XCTAssertEqual(report.value(forHTTPHeaderField: "Trigger"), "Purchase")
        let body = try XCTUnwrap(report.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let storeData = body["store_data"] as? [String: Any]
        XCTAssertEqual(storeData?["receipt"] as? String, "signed-jws")
        XCTAssertEqual(storeData?["transaction_id"] as? String, "tx-1")

        XCTAssertEqual(subMgmt.storeKit.finishedTransactions.map(\.id), ["tx-1"])

        // The refreshed entitlements are emitted into the stream (buffered,
        // so subscribing after the fact still receives them).
        var received: [String: Qonversion.Entitlement]?
        for await update in subMgmt.purchasesManager.entitlementsUpdates() {
            received = update
            break
        }
        XCTAssertEqual(received?.keys.sorted(), ["premium"])
    }

    // MARK: - 3. offline report, replayed on the next launch

    func testOfflineReportIsReplayedByTheNextLaunch() async throws {
        world.stubHappyUser()
        world.network.stub("POST", "/v4/users/*/purchases", transportError: URLError(.notConnectedToInternet))
        let transaction = Qonversion.Transaction(id: "tx-off", originalId: "tx-off", productId: "com.app.pro", jws: "jws-off")

        await world.purchasesManager.handle(transactions: [transaction])
        XCTAssertEqual(world.assembly.servicesAssembly.miscAssembly.requestsStorage().fetchRequests().count, 1,
                       "the failed report must be queued for the offline replay")

        // "Next launch": a fresh assembly over the SAME UserDefaults with a
        // healthy network — the queued report must be delivered exactly once.
        let nextLaunch = SdkWorld(userDefaults: world.userDefaults)
        nextLaunch.network.stub("POST", "/v4/users/*/purchases", body: #"{"object": "purchase"}"#)
        nextLaunch.assembly.replayStoredRequests()

        let deadline = Date().addingTimeInterval(3)
        while nextLaunch.network.recordedRequests("POST", "/v4/users/*/purchases").isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        // Delivered exactly once, and the queue is drained.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let replayedRequests = nextLaunch.network.recordedRequests("POST", "/v4/users/*/purchases")
        XCTAssertEqual(replayedRequests.count, 1, "the queued report must be delivered exactly once")
        let replayed = try XCTUnwrap(replayedRequests.first)
        // The first session sent this request maxTransportRetries + 1 times
        // before giving up on the transport; the replay is the one after that.
        // A hardcoded "2" would have been the count only if the in-session
        // retries were pretended away.
        let sendsInTheFirstSession: Int = RequestProcessor.maxTransportRetries + 1
        XCTAssertEqual(replayed.value(forHTTPHeaderField: "Attempt"), "\(sendsInTheFirstSession + 1)",
                       "the replay continues the true attempt sequence")
        XCTAssertEqual(replayed.value(forHTTPHeaderField: "Trigger"), "HandleStoreKit2Transactions", "the original flow's trigger survives the queue")
        XCTAssertTrue(nextLaunch.assembly.servicesAssembly.miscAssembly.requestsStorage().fetchRequests().isEmpty, "the delivered request leaves the queue")
    }

    // MARK: - 4. identity switch cascades through the graph

    func testIdentitySwitchMovesTheUidAndInvalidatesUserScopedCaches() async throws {
        world.stubHappyUser()
        _ = try await world.userManager.obtainUser()
        let originalUid: String = world.uid

        // Warm a user-scoped cache.
        world.network.stub("GET", "/v4/products", body: #"{"object": "list", "data": [{"id": "pro", "apple_product_id": "com.app.pro"}]}"#)
        _ = try await world.productsManager.products()

        world.network.stub("GET", "/v4/identities/*", status: 404, body: #"{"error": {"code": "not_found", "message": "no identity", "type": "invalid_request"}}"#)
        world.network.stub("POST", "/v4/identities", body: #"{"object": "identity", "id": "ext-1", "user_id": "QON_linked_uid"}"#)
        world.network.stub("GET", "/v4/users/QON_linked_uid", body: #"{"id": "QON_linked_uid", "created_at": "2026-07-27T10:00:00Z", "environment": "prod"}"#)

        let user = try await world.userManager.identify("ext-1")

        XCTAssertEqual(user.id, "QON_linked_uid")
        XCTAssertEqual(world.uid, "QON_linked_uid")
        XCTAssertNotEqual(world.uid, originalUid)

        // The products cache belonged to the previous user — the next call refetches.
        _ = try await world.productsManager.products()
        XCTAssertEqual(world.network.recordedRequests("GET", "/v4/products").count, 2)
    }

    // MARK: - 5. logout returns to the original anonymous user

    func testLogoutRestoresTheOriginalUidForTheNextRequests() async throws {
        world.stubHappyUser()
        _ = try await world.userManager.obtainUser()
        let originalUid: String = world.uid

        world.network.stub("GET", "/v4/identities/*", status: 404, body: #"{"error": {"code": "not_found", "message": "no identity", "type": "invalid_request"}}"#)
        world.network.stub("POST", "/v4/identities", body: #"{"object": "identity", "id": "ext-1", "user_id": "QON_linked_uid"}"#)
        world.network.stub("GET", "/v4/users/QON_linked_uid", body: #"{"id": "QON_linked_uid", "created_at": "2026-07-27T10:00:00Z", "environment": "prod"}"#)
        _ = try await world.userManager.identify("ext-1")
        XCTAssertEqual(world.uid, "QON_linked_uid")

        await world.userManager.logout()

        XCTAssertEqual(world.uid, originalUid, "logout returns to the install's original anonymous user")

        // The next demand upserts exactly the original uid.
        world.network.stub("POST", "/v4/users", body: #"{"id": "\#(originalUid)", "created_at": "2026-07-27T10:00:00Z", "environment": "prod"}"#)
        let user = try await world.userManager.obtainUser()
        XCTAssertEqual(user.id, originalUid)
    }

    // MARK: - 6. properties flush strictly before remote config

    func testPendingPropertiesReachTheBackendBeforeTheRemoteConfig() async throws {
        world.stubHappyUser()
        world.network.stub("POST", "/v4/users/*/properties", body: #"{"object": "list", "saved_properties": [], "property_errors": []}"#)
        world.network.stub("GET", "/v4/remote-config", body: #"{"payload": {"k": "v"}, "source": {"uid": "s1", "name": "main", "type": "remote_configuration", "assignment_type": "auto", "context_key": null}}"#)

        world.userPropertiesManager.setUserProperty(key: .email, value: "a@b.com")
        _ = try await world.remoteConfigManager.loadRemoteConfig(contextKey: nil)

        let all = world.network.allRequests()
        let propertiesIndex = all.firstIndex { $0.httpMethod == "POST" && ($0.url?.path.hasSuffix("/properties") ?? false) }
        let configIndex = all.firstIndex { $0.httpMethod == "GET" && ($0.url?.path.hasSuffix("/remote-config") ?? false) }
        let propertiesAt = try XCTUnwrap(propertiesIndex, "the pending batch must be flushed for fresh segmentation")
        let configAt = try XCTUnwrap(configIndex)
        XCTAssertLessThan(propertiesAt, configAt, "segmentation data must reach the backend before the config is computed")
    }

    // MARK: - 7. the SDK-wide critical latch over per-service processors

    func testACriticalErrorLatchesEveryService() async throws {
        world.stubHappyUser()
        world.network.stub("GET", "/v4/users/*/entitlements", status: 401, body: #"{"error": {"code": "unauthorized", "message": "revoked", "type": "auth"}}"#)
        world.network.stub("GET", "/v4/products", body: #"{"object": "list", "data": []}"#)

        _ = try? await world.entitlementsManager.entitlements()
        _ = try? await world.entitlementsManager.entitlements()

        XCTAssertEqual(world.network.recordedRequests("GET", "/v4/users/*/entitlements").count, 1, "the latched processor must not hammer the backend")

        // The processors stay per service, the latch does not: a 401 means the
        // project key itself is revoked, so every other service is dead too —
        // exactly what the single QNAPIClient of the ObjC SDK did.
        do {
            _ = try await world.productsManager.products()
            XCTFail("Expected the revoked key to stop the products service as well")
        } catch {
            // Products wraps the failure in its own type; the latched critical
            // error is the cause underneath.
            let underlying = (error as? QonversionError)?.error as? QonversionError
            XCTAssertEqual(underlying?.type, .critical)
        }
        XCTAssertTrue(world.network.recordedRequests("GET", "/v4/products").isEmpty, "a revoked key must stop every service before the network")
    }

    // MARK: - 7b. launch replay vs the unfinished-transaction sweep

    func testAQueuedReportAndTheSameUnfinishedTransactionArePostedOnce() async throws {
        // What initialize() does: the offline replay and the unfinished sweep
        // start concurrently. Both hold the same purchase — the backend must
        // see exactly one POST for it.
        let subMgmt = SdkWorld(userDefaults: TestDefaults.makeIsolated(), launchMode: .subscriptionManagement)
        subMgmt.stubHappyUser()
        subMgmt.network.stub("POST", "/v4/users/*/purchases", body: #"{"object": "purchase"}"#)
        subMgmt.network.stub("GET", "/v4/users/*/entitlements", body: #"{"object": "list", "data": []}"#)
        let transaction = Qonversion.Transaction(id: "tx-dup", originalId: "tx-dup", productId: "com.app.pro", jws: "signed-jws")
        subMgmt.storeKit.fetchUnfinishedResult = [transaction]
        subMgmt.assembly.servicesAssembly.miscAssembly.requestsStorage().append(StoredRequest(
            url: "https://api2.qonversion.io/v4/users/" + subMgmt.uid + "/purchases",
            method: "POST",
            body: Data(#"{"store_data": {"transaction_id": "tx-dup"}}"#.utf8),
            dedupKey: "createPurchase-" + subMgmt.uid + "-tx-dup",
            transactionId: "tx-dup"
        ))

        subMgmt.assembly.replayStoredRequests()
        await subMgmt.purchasesManager.processUnfinishedTransactions()
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(subMgmt.network.recordedRequests("POST", "/v4/users/*/purchases").count, 1,
                       "the replay and the sweep must not both report the same transaction")
    }

    // MARK: - 8. intro eligibility over the real facade and manager

    func testEligibilityFlowsThroughTheRealGraph() async throws {
        world.stubHappyUser()
        world.network.stub("GET", "/v4/products", body: #"{"object": "list", "data": [{"id": "pro", "apple_product_id": "com.app.pro"}]}"#)

        let result = try await world.productsManager.checkTrialIntroEligibility(productIds: ["pro", "missing"])

        // Honest scope, deliberately left as-is: StoreKit.Product cannot be
        // constructed outside a real StoreKit session, so over the object
        // graph both ids can only resolve to .unknown. The eligibility
        // resolution itself is pinned in ProductsManagerTests (over the
        // injectable check seam) and in the StoreKitTest layer, which runs the
        // real StoreKit over an SKTestSession. What this smoke test pins is
        // the part that IS reachable here: the real manager consulted the real
        // backend catalog first, and an id absent from it does not fail the
        // call.
        XCTAssertEqual(world.network.recordedRequests("GET", "/v4/products").count, 1)
        XCTAssertEqual(result["pro"], .unknown)
        XCTAssertEqual(result["missing"], .unknown)
    }
}
