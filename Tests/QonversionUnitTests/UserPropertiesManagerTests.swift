//
//  UserPropertiesManagerTests.swift
//  QonversionUnitTests
//
//  Fixation tests for UserPropertiesManager: lock in the current behavior as-is.
//

import XCTest
@testable import Qonversion

final class IncrementalDelayCalculatorClampTests: XCTestCase {

    func testHugeRetryCountDoesNotCrashAndRespectsMaxDelay() {
        let calculator = IncrementalDelayCalculator()

        let delay = calculator.countDelay(minDelay: 5, retriesCount: 500)

        XCTAssertLessThanOrEqual(delay, 1000)
        XCTAssertGreaterThan(delay, 0)
    }
}

final class UserPropertiesManagerTests: XCTestCase {

    private var requestProcessor: MockRequestProcessor!
    private var propertiesStorage: UserPropertiesStorage!
    private var integrationsCollector: MockIntegrationsInfoCollector!
    private var userManager: MockUserManager!
    private var manager: UserPropertiesManager!

    override func setUp() {
        super.setUp()
        requestProcessor = MockRequestProcessor()
        propertiesStorage = UserPropertiesStorage()
        userManager = MockUserManager()
        userManager.user = try? JSONDecoder.qonversionTest.decode(Qonversion.User.self, from: Data(#"{"id": "test-user-id", "created_at": "2023-11-14T22:13:20Z", "environment": "sandbox"}"#.utf8))
        integrationsCollector = MockIntegrationsInfoCollector()
        manager = UserPropertiesManager(
            requestProcessor: requestProcessor,
            propertiesStorage: propertiesStorage,
            delayCalculator: IncrementalDelayCalculator(),
            userIdProvider: InternalConfig(userId: "test-user-id"),
            userManager: userManager,
            integrationsInfoCollector: integrationsCollector,
            logger: LoggerWrapper()
        )
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    override func tearDown() {
        // Dropping the manager without awaiting any scheduled sending task (min 5s delay):
        // tests never wait for it to avoid flakiness.
        manager = nil
        propertiesStorage = nil
        requestProcessor = nil
        super.tearDown()
    }

    // MARK: - setUserProperty

    // Fixates current behavior: the `.custom` defined key is rejected — nothing is saved.
    func testSetUserPropertyWithCustomKeyIsRejected() {
        manager.setUserProperty(key: .custom, value: "some value")

        XCTAssertTrue(propertiesStorage.all().isEmpty)
    }

    func testSetUserPropertyWithDefinedKeySavesRawKeyToStorage() {
        manager.setUserProperty(key: .email, value: "test@qonversion.io")

        let saved = propertiesStorage.all()
        XCTAssertEqual(saved, [Qonversion.UserProperty(key: "_q_email", value: "test@qonversion.io")])
    }

    // MARK: - setCustomUserProperty

    // Fixates current behavior: an empty value is silently ignored.
    func testSetCustomUserPropertyWithEmptyValueIsIgnored() {
        manager.setCustomUserProperty(key: "my_key", value: "")

        XCTAssertTrue(propertiesStorage.all().isEmpty)
    }

    func testSetCustomUserPropertyWithNonEmptyValueIsSaved() {
        manager.setCustomUserProperty(key: "my_key", value: "my_value")

        XCTAssertEqual(propertiesStorage.all(), [Qonversion.UserProperty(key: "my_key", value: "my_value")])
    }

    // MARK: - integrations data auto-collection (production parity)

    func testCollectIntegrationsDataStoresAvailableIntegrationIds() {
        integrationsCollector.adjustUserIdResult = "adjust-123"
        integrationsCollector.appsFlyerUserIdResult = "af-456"
        integrationsCollector.facebookAnonymousIdResult = "fb-789"

        manager.collectIntegrationsData()

        let stored: [String: String] = Dictionary(propertiesStorage.all().map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(stored["_q_adjust_adid"], "adjust-123")
        XCTAssertEqual(stored["_q_appsflyer_user_id"], "af-456")
        XCTAssertEqual(stored["_q_fb_anon_id"], "fb-789")
    }

    func testCollectIntegrationsDataSkipsMissingIntegrations() {
        integrationsCollector.adjustUserIdResult = nil
        integrationsCollector.appsFlyerUserIdResult = nil
        integrationsCollector.facebookAnonymousIdResult = nil

        manager.collectIntegrationsData()

        XCTAssertTrue(propertiesStorage.all().isEmpty)
    }

    // MARK: - defined property keys

    func testTenjinKeyMatchesTheCrossPlatformContract() {
        XCTAssertEqual(Qonversion.UserPropertyKey.tenjinAnalyticsInstallationId.rawValue, "_q_tenjin_aiid")
    }

    // MARK: - sendProperties

    func testSendPropertiesSuccessClearsStorageAndSendsRequest() async throws {
        propertiesStorage.save(Qonversion.UserProperty(key: "_q_email", value: "test@qonversion.io"))
        requestProcessor.results = [SendUserPropertiesResult(savedProperties: [], propertyErrors: [])]

        try await manager.sendProperties()

        XCTAssertTrue(propertiesStorage.all().isEmpty)
        XCTAssertEqual(requestProcessor.processedRequests.count, 1)
        guard case let .sendProperties(userId, _, body, _) = requestProcessor.processedRequests[0] else {
            return XCTFail("Expected a .sendProperties request")
        }
        XCTAssertEqual(userId, "test-user-id")
        XCTAssertEqual(body.count, 1)
    }

    // Fixates current behavior: per-property errors in a successful response are only
    // logged — the storage is cleared anyway.
    func testSendPropertiesSuccessWithPropertyErrorsStillClearsStorage() async throws {
        propertiesStorage.save(Qonversion.UserProperty(key: "broken_key", value: "value"))
        requestProcessor.results = [
            SendUserPropertiesResult(
                savedProperties: [],
                propertyErrors: [SendUserPropertiesResult.UserPropertyError(key: "broken_key", error: "invalid")]
            )
        ]

        try await manager.sendProperties()

        XCTAssertTrue(propertiesStorage.all().isEmpty)
    }

    func testSendPropertiesWithEmptyStorageDoesNotHitProcessor() async throws {
        try await manager.sendProperties()

        XCTAssertTrue(requestProcessor.processedRequests.isEmpty)
    }

    // Fixates current behavior: a processor error is swallowed (sendProperties does not
    // rethrow), the properties stay in storage, and a retry is scheduled with a delay of
    // at least 5 seconds (not awaited here).
    func testSendPropertiesFailureKeepsPropertiesInStorage() async throws {
        let property = Qonversion.UserProperty(key: "_q_name", value: "John")
        propertiesStorage.save(property)
        requestProcessor.error = MockError.stubbed

        try await manager.sendProperties()

        XCTAssertEqual(propertiesStorage.all(), [property])
        XCTAssertEqual(requestProcessor.processedRequests.count, 1)
    }

    // MARK: - forceful sending

    func testForceSendPropertiesWaitsOutTheBatchInFlightAndSendsTheRest() async throws {
        // A silent early return here breaks both forceSendProperties() and the
        // properties-before-remote-config invariant.
        propertiesStorage.save(Qonversion.UserProperty(key: "first", value: "1"))
        let gate = PropertiesAsyncGate()
        requestProcessor.onProcess = { await gate.wait() }
        requestProcessor.results = [
            SendUserPropertiesResult(savedProperties: [], propertyErrors: []),
            SendUserPropertiesResult(savedProperties: [], propertyErrors: []),
        ]

        async let batchInFlight: Void = manager.sendProperties()
        await waitUntil { self.requestProcessor.processedRequests.count == 1 }
        propertiesStorage.save(Qonversion.UserProperty(key: "second", value: "2"))
        async let forced: Void = manager.sendProperties(force: true)
        try? await Task.sleep(nanoseconds: 50_000_000)
        await gate.open()
        requestProcessor.onProcess = nil
        _ = try await batchInFlight
        _ = try await forced

        XCTAssertEqual(requestProcessor.processedRequests.count, 2, "force must send what the in-flight batch did not cover")
        XCTAssertTrue(propertiesStorage.all().isEmpty)
    }

    func testForceSendPropertiesReturnsWhenNothingIsPending() async throws {
        try await manager.sendProperties(force: true)

        XCTAssertTrue(requestProcessor.processedRequests.isEmpty)
    }

    func testForceSendPropertiesStopsAfterAFailedSend() async throws {
        propertiesStorage.save(Qonversion.UserProperty(key: "first", value: "1"))
        requestProcessor.error = MockError.stubbed

        try await manager.sendProperties(force: true)

        XCTAssertEqual(requestProcessor.processedRequests.count, 1, "a failing backend must not be hammered in a loop")
        XCTAssertEqual(propertiesStorage.all().count, 1)
    }

    // MARK: - userProperties

    func testUserPropertiesReturnsPropertiesFromProcessor() async throws {
        let properties: [Qonversion.UserProperty] = [
            Qonversion.UserProperty(key: "_q_email", value: "test@qonversion.io"),
            Qonversion.UserProperty(key: "custom_key", value: "custom_value"),
        ]
        requestProcessor.results = [ListEnvelope<Qonversion.UserProperty>(data: properties)]

        let result = try await manager.userProperties()

        XCTAssertEqual(result.properties, properties)
        XCTAssertEqual(result.flatDefinedPropertiesMap[.email], "test@qonversion.io")
        XCTAssertEqual(result.customProperties, [Qonversion.UserProperty(key: "custom_key", value: "custom_value")])
        XCTAssertEqual(requestProcessor.processedRequests.count, 1)
        guard case let .getProperties(userId, _, _) = requestProcessor.processedRequests[0] else {
            return XCTFail("Expected a .getProperties request")
        }
        XCTAssertEqual(userId, "test-user-id")
    }

    // Fixates current behavior: processor errors are swallowed via `try?` and an empty
    // properties list is returned instead of throwing.
    func testUserPropertiesRethrowsTheRequestError() async {
        // The caller must be able to tell "no properties" from "request failed".
        requestProcessor.error = MockError.stubbed

        do {
            _ = try await manager.userProperties()
            XCTFail("Expected the request error to propagate")
        } catch {
            XCTAssertEqual(error as? MockError, .stubbed)
        }
    }

    func testMalformedCustomPropertyKeyIsRejected() {
        manager.setCustomUserProperty(key: "user name!", value: "v")

        XCTAssertTrue(propertiesStorage.all().isEmpty, "the production key contract rejects invalid keys before the batch")
    }

    // MARK: - collectAppleSearchAdsAttribution

    // Smoke test only: AdServices attribution token retrieval is unavailable/unentitled
    // in the unit test environment, so we just verify the call does not crash.
    func testCollectAppleSearchAdsAttributionDoesNotCrash() {
        manager.collectAppleSearchAdsAttribution()
    }

    func testAppleSearchAdsTokenIsSentAfterTheUserGateAndAcceptsAnEmptyAcknowledgement() async throws {
        // The endpoint answers with an empty body: decoding it as a String
        // turned every successful call into an invalidResponse failure.
        requestProcessor.results = [EmptyApiResponse()]

        try await manager.sendAppleSearchAdsToken("attribution-token", requestedAt: 1_700_000_000)

        XCTAssertEqual(userManager.obtainUserCallsCount, 1, "no data is sent before the backend user exists")
        XCTAssertEqual(requestProcessor.processedRequests.count, 1)
        guard case let .appleSearchAds(userId, _, body, _) = requestProcessor.processedRequests[0] else {
            return XCTFail("Expected an .appleSearchAds request")
        }
        XCTAssertEqual(userId, "test-user-id")
        XCTAssertEqual(body["token"] as? String, "attribution-token")
        XCTAssertEqual(body["provider"] as? String, "apple_adservices_token")
        XCTAssertEqual(body["requested_at"] as? Int, 1_700_000_000, "the backend matches the attribution window by this timestamp")
    }

    func testAppleSearchAdsTokenIsNotSentWhenTheUserGateFails() async {
        userManager.error = MockError.stubbed

        do {
            try await manager.sendAppleSearchAdsToken("attribution-token")
            XCTFail("Expected the gate error to propagate")
        } catch {
            XCTAssertEqual(error as? MockError, .stubbed)
        }
        XCTAssertTrue(requestProcessor.processedRequests.isEmpty)
    }

    // MARK: - user gate

    // Data-sending flows must pass the user gate first: the backend user has to
    // exist before properties are sent.
    func testSendPropertiesObtainsUserBeforeSendingRequest() async throws {
        manager.setCustomUserProperty(key: "k", value: "v")
        requestProcessor.results = [SendUserPropertiesResult(savedProperties: [], propertyErrors: [])]

        try await manager.sendProperties()

        XCTAssertEqual(userManager.obtainUserCallsCount, 1)
        XCTAssertEqual(requestProcessor.processedRequests.count, 1)
    }

    func testSendPropertiesDoesNotFireWhenUserGateFails() async throws {
        manager.setCustomUserProperty(key: "k", value: "v")
        userManager.error = MockError.stubbed

        try? await manager.sendProperties()

        XCTAssertTrue(requestProcessor.processedRequests.isEmpty, "no request may be sent when the user is not created")
        XCTAssertEqual(propertiesStorage.all().count, 1, "properties must be kept for a later retry")
    }

    func testUserPropertiesObtainsUserBeforeRequest() async throws {
        requestProcessor.results = [ListEnvelope<Qonversion.UserProperty>(data: [])]

        _ = try await manager.userProperties()

        XCTAssertEqual(userManager.obtainUserCallsCount, 1)
    }
}

extension JSONDecoder {
    static var qonversionTest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The strategy the SDK actually installs.
    static var qonversionTolerantTest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .qonversionTolerant
        return decoder
    }
}

/// A reusable async gate: wait() suspends until open() is called.
private actor PropertiesGateStorage {
    var isOpen = false
    var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private final class PropertiesAsyncGate: @unchecked Sendable {
    private let storage = PropertiesGateStorage()
    func open() async { await storage.open() }
    func wait() async { await storage.wait() }
}

/// Records the observer removals the manager performs on deinit.
final class SpyNotificationCenter: NotificationCenter, @unchecked Sendable {

    private(set) var removedObservers: [Any] = []

    override func removeObserver(_ observer: Any) {
        removedObservers.append(observer)
        super.removeObserver(observer)
    }
}

final class UserPropertiesObserverTests: XCTestCase {

    private func makeManager(center: NotificationCenter, name: Notification.Name, processor: MockRequestProcessor = MockRequestProcessor(), storage: UserPropertiesStorage = UserPropertiesStorage()) -> UserPropertiesManager {
        let userManager = MockUserManager()
        userManager.user = try? JSONDecoder.qonversionTest.decode(Qonversion.User.self, from: Data(#"{"id": "u", "created_at": "2023-11-14T22:13:20Z"}"#.utf8))

        return UserPropertiesManager(
            requestProcessor: processor,
            propertiesStorage: storage,
            delayCalculator: IncrementalDelayCalculator(),
            userIdProvider: InternalConfig(userId: "u"),
            userManager: userManager,
            integrationsInfoCollector: MockIntegrationsInfoCollector(),
            logger: LoggerWrapper(),
            notificationCenter: center,
            backgroundNotificationName: name
        )
    }

    func testTheBackgroundObserverIsRemovedOnDeinit() {
        // A token-less registration outlives the manager: the closure stays in
        // the notification center for the life of the process.
        let center = SpyNotificationCenter()
        var manager: UserPropertiesManager? = makeManager(center: center, name: Notification.Name("test.background"))
        XCTAssertNotNil(manager)

        manager = nil

        XCTAssertEqual(center.removedObservers.count, 1, "the background flush observer must be unregistered")
    }

    func testTheBackgroundNotificationFlushesThePendingBatch() async {
        // Proves the subscription is live, on every platform: the batch waits
        // on a delay timer that never fires once the process is suspended.
        let center = SpyNotificationCenter()
        let name = Notification.Name("test.background.flush")
        let processor = MockRequestProcessor()
        processor.results = [SendUserPropertiesResult(savedProperties: [], propertyErrors: [])]
        let storage = UserPropertiesStorage()
        let manager: UserPropertiesManager = makeManager(center: center, name: name, processor: processor, storage: storage)
        manager.setCustomUserProperty(key: "k", value: "v")

        center.post(name: name, object: nil)

        let deadline = Date().addingTimeInterval(3)
        while processor.processedRequests.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(processor.processedRequests.count, 1)
        XCTAssertTrue(storage.all().isEmpty)
    }
}
