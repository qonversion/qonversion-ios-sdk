//
//  UserPropertiesManagerTests.swift
//  QonversionUnitTests
//
//  Fixation tests for UserPropertiesManager: lock in the current behavior as-is.
//

import XCTest
#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
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
        // A count alone would also pass if force re-sent the SAME batch: what
        // is being pinned is that the second request carries the property the
        // first one could not have covered.
        XCTAssertEqual(sentPropertyKeys(at: 0), ["first"])
        XCTAssertEqual(sentPropertyKeys(at: 1), ["second"])
        XCTAssertTrue(propertiesStorage.all().isEmpty)
    }

    /// The property keys carried by the n-th .sendProperties request body.
    private func sentPropertyKeys(at index: Int) -> [String] {
        guard index < requestProcessor.processedRequests.count else {
            XCTFail("No request at index \(index)")
            return []
        }
        guard case let .sendProperties(_, _, body, _) = requestProcessor.processedRequests[index] else {
            XCTFail("Expected a .sendProperties request at index \(index)")
            return []
        }
        guard let items: RequestBodyArray = body["properties"] as? RequestBodyArray else {
            XCTFail("Expected a `properties` array in the body")
            return []
        }
        return items.compactMap { ($0 as? RequestBodyDict)?["key"] as? String }.sorted()
    }

    // MARK: - user switch

    func testAUserSwitchDropsThePendingPropertiesBatch() async throws {
        // Properties queued under the previous uid must never be posted under
        // the new one.
        manager.setCustomUserProperty(key: "first", value: "1")
        XCTAssertFalse(propertiesStorage.all().isEmpty, "precondition: the property is pending")

        manager.userDidChange()

        XCTAssertTrue(propertiesStorage.all().isEmpty, "the previous user's batch is dropped")
        try await manager.sendProperties(force: true)
        XCTAssertTrue(requestProcessor.processedRequests.isEmpty, "nothing is sent under the new uid")
    }

    func testThePendingPropertiesBatchIsTornDownWithTheOtherCaches() {
        XCTAssertEqual(manager.userChangeTeardownPriority, UserChangeTeardownPriority.cache)
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

/// A one-shot "it finished" marker: lets a test bound an await that would
/// otherwise hang forever, so a regression fails instead of stalling the suite.
private actor DoneFlag {
    private var isDone = false

    func markDone() { isDone = true }

    func value() -> Bool { isDone }
}

private func waitForCompletion(of flag: DoneFlag, timeout: TimeInterval) async -> Bool {
    let deadline: Date = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await flag.value() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    return await flag.value()
}

private func pollUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
    let deadline: Date = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
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
        XCTAssertTrue(center.removedObservers.isEmpty, "the registration must stay live while the manager is alive")

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

    func testEveryHostsBackgroundNotificationNameIsMapped() {
        // Runs on every platform and covers all of them: an #if-guarded
        // assertion only ever compiles the arm for the platform under test, so
        // a broken mapping for one of the others ships green. A name nothing
        // posts silently drops the pending batch on that platform.
        XCTAssertEqual(
            UserPropertiesManager.backgroundFlushNotificationName(for: .watchExtension).rawValue,
            "NSExtensionHostDidEnterBackgroundNotification"
        )
        XCTAssertEqual(
            UserPropertiesManager.backgroundFlushNotificationName(for: .uiKitApplication).rawValue,
            "UIApplicationDidEnterBackgroundNotification"
        )
        XCTAssertEqual(
            UserPropertiesManager.backgroundFlushNotificationName(for: .appKitApplication).rawValue,
            "NSApplicationDidResignActiveNotification"
        )
        XCTAssertNotEqual(
            UserPropertiesManager.backgroundFlushNotificationName(for: .watchExtension),
            UserPropertiesManager.backgroundFlushNotificationName(for: .uiKitApplication),
            "the watch host must not fall through to the UIKit name — watchOS imports UIKit but has no UIApplication"
        )
    }

    func testTheObservedNotificationIsTheOneTheCurrentPlatformPosts() {
        // The mapping above is spelled with string literals; this pins the
        // literal for the platform under test to the constant the system
        // actually posts, so the table cannot drift away from the frameworks.
        let observed: Notification.Name = UserPropertiesManager.backgroundNotificationName

        #if os(watchOS)
        XCTAssertEqual(UserPropertiesManager.currentBackgroundFlushHost, .watchExtension)
        XCTAssertEqual(observed, .NSExtensionHostDidEnterBackground)
        #elseif canImport(UIKit)
        XCTAssertEqual(UserPropertiesManager.currentBackgroundFlushHost, .uiKitApplication)
        XCTAssertEqual(observed, UIApplication.didEnterBackgroundNotification)
        #elseif canImport(AppKit)
        XCTAssertEqual(UserPropertiesManager.currentBackgroundFlushHost, .appKitApplication)
        XCTAssertEqual(observed, NSApplication.didResignActiveNotification)
        #endif
    }
}

/// The pending batch belongs to the uid that queued it: it must reach the
/// backend under that uid before the switch completes, and it must never be
/// carried over to the user the SDK switches to.
final class UserPropertiesUserSwitchTests: XCTestCase {

    private let oldUid = "old-uid"
    private let newUid = "new-uid"

    private func makeUser(id: String) throws -> Qonversion.User {
        let json = #"{"id": "\#(id)", "created_at": "2023-11-14T22:13:20Z"}"#
        return try JSONDecoder.qonversionTest.decode(Qonversion.User.self, from: Data(json.utf8))
    }

    private struct Graph {
        let userManager: UserManager
        let propertiesManager: UserPropertiesManager
        let propertiesStorage: UserPropertiesStorage
        let processor: MockRequestProcessor
        let config: InternalConfig
        /// The gate the properties manager is wired to. It is a stub, not the
        /// real UserManager above: the handed-over post is expected to skip the
        /// gate entirely, and a stub is what makes the call count observable.
        let propertiesUserManager: MockUserManager
    }

    private func makeGraph(originalUid: String) throws -> Graph {
        let config = InternalConfig(userId: oldUid)
        let storage = MockLocalStorage()
        storage.set(string: originalUid, forKey: UserServiceStorageKeys.originalUserIdKey.rawValue)
        let userService = MockUserService()
        let oldUser: Qonversion.User = try makeUser(id: oldUid)
        userService.createUserResult = oldUser
        userService.userResult = try makeUser(id: newUid)
        userService.identityLinkedUid = newUid
        let notifier = UserChangesNotifier()
        let logger = LoggerWrapper()
        let userManager = UserManager(userService: userService, localStorage: storage, internalConfig: config, userChangesNotifier: notifier, logger: logger)

        let processor = MockRequestProcessor()
        let sendResult = SendUserPropertiesResult(savedProperties: [], propertyErrors: [])
        processor.results = [sendResult]
        let propertiesStorage = UserPropertiesStorage()
        // A stub gate, so "the post never calls obtainUser" is observable as a
        // call count. It is not a claim that the real gate would misbehave —
        // UserManager is an actor, a reentrant call would suspend, not
        // deadlock. The post skips the gate because the outgoing user provably
        // exists by then, so the call would buy nothing.
        let propertiesUserManager = MockUserManager()
        propertiesUserManager.user = oldUser
        let propertiesManager = UserPropertiesManager(
            requestProcessor: processor,
            propertiesStorage: propertiesStorage,
            delayCalculator: IncrementalDelayCalculator(),
            userIdProvider: config,
            userManager: propertiesUserManager,
            integrationsInfoCollector: MockIntegrationsInfoCollector(),
            logger: logger
        )
        notifier.add(observer: propertiesManager)

        return Graph(userManager: userManager, propertiesManager: propertiesManager, propertiesStorage: propertiesStorage, processor: processor, config: config, propertiesUserManager: propertiesUserManager)
    }

    private func sentPropertyUserIds(_ processor: MockRequestProcessor) -> [String] {
        return processor.processedRequests.compactMap { request in
            guard case let .sendProperties(userId, _, _, _) = request else { return nil }
            return userId
        }
    }

    private func sentPropertyKeys(_ processor: MockRequestProcessor, at index: Int) -> [String] {
        let bodies: [RequestBodyDict] = processor.processedRequests.compactMap { request in
            guard case let .sendProperties(_, _, body, _) = request else { return nil }
            return body
        }
        guard index < bodies.count else {
            XCTFail("No .sendProperties request at index \(index)")
            return []
        }
        guard let items: RequestBodyArray = bodies[index]["properties"] as? RequestBodyArray else {
            XCTFail("Expected a `properties` array in the body")
            return []
        }

        return items.compactMap { ($0 as? RequestBodyDict)?["key"] as? String }.sorted()
    }

    func testIdentifySendsThePendingBatchUnderTheOldUid() async throws {
        let graph: Graph = try makeGraph(originalUid: oldUid)
        _ = try await graph.userManager.obtainUser()
        graph.propertiesManager.setCustomUserProperty(key: "my_key", value: "my_value")

        _ = try await graph.userManager.identify("external-id")

        XCTAssertEqual(graph.config.userId, newUid, "the identify must have switched the user")
        XCTAssertTrue(graph.propertiesStorage.all().isEmpty, "the new user must start with an empty batch")
        // The switch no longer implies delivery: the batch is handed to a
        // background post, so the delivery is awaited here rather than assumed.
        await pollUntil { !self.sentPropertyUserIds(graph.processor).isEmpty }
        XCTAssertEqual(sentPropertyUserIds(graph.processor), [oldUid], "the batch belongs to the user that queued it")
        XCTAssertEqual(
            graph.propertiesUserManager.obtainUserCallsCount,
            0,
            "the post goes out under the uid it was handed, without asking the user gate"
        )
    }

    func testLogoutSendsThePendingBatchUnderTheIdentifiedUid() async throws {
        // The uid moved away from the install's anonymous user, so the logout
        // restores it — the same switch, reached from the other entry point.
        let graph: Graph = try makeGraph(originalUid: "anon-uid")
        _ = try await graph.userManager.obtainUser()
        graph.propertiesManager.setCustomUserProperty(key: "my_key", value: "my_value")

        await graph.userManager.logout()

        XCTAssertEqual(graph.config.userId, "anon-uid", "the logout must have restored the original user")
        XCTAssertTrue(graph.propertiesStorage.all().isEmpty, "the restored user must start with an empty batch")
        await pollUntil { !self.sentPropertyUserIds(graph.processor).isEmpty }
        XCTAssertEqual(sentPropertyUserIds(graph.processor), [oldUid], "the batch belongs to the user that queued it")
        XCTAssertEqual(graph.propertiesUserManager.obtainUserCallsCount, 0, "the post does not go through the user gate")
    }

    // MARK: - the fire-and-forget handoff

    func testAStalledPropertiesPostDoesNotHoldUpTheUserSwitch() async throws {
        // The switch used to await the post, and the post awaits the network:
        // an identify at launch or a logout behind a sign-out button inherited
        // the request timeout (60s by default, twice that when a round trip was
        // already in flight). The batch is handed over synchronously now, so
        // the switch never touches the network at all.
        let graph: Graph = try makeGraph(originalUid: oldUid)
        _ = try await graph.userManager.obtainUser()
        let stall = PropertiesAsyncGate()
        graph.processor.onProcess = { await stall.wait() }
        graph.propertiesManager.setCustomUserProperty(key: "my_key", value: "my_value")

        let startedAt: Date = Date()
        _ = try await graph.userManager.identify("external-id")
        let elapsed: TimeInterval = Date().timeIntervalSince(startedAt)
        let batchAfterSwitch: [Qonversion.UserProperty] = graph.propertiesStorage.all()
        await stall.open()

        XCTAssertLessThan(elapsed, 1, "the user switch must not wait for the properties post at all")
        XCTAssertEqual(graph.config.userId, newUid, "the identify must have switched the user")
        XCTAssertTrue(batchAfterSwitch.isEmpty, "the batch is handed over before the switch returns; the new user starts clean")
    }

    func testTheHandedOverBatchIsDeliveredUnderTheOldUidAfterTheSwitch() async throws {
        // The payoff over waiting: a post that is merely slow still lands, and
        // it lands under the user that queued it — long after that user stopped
        // being the current one.
        let graph: Graph = try makeGraph(originalUid: oldUid)
        _ = try await graph.userManager.obtainUser()
        let slowRequest = PropertiesAsyncGate()
        graph.processor.onProcess = { await slowRequest.wait() }
        graph.propertiesManager.setCustomUserProperty(key: "old_user_key", value: "1")

        _ = try await graph.userManager.identify("external-id")
        XCTAssertEqual(graph.config.userId, newUid, "the identify must have switched the user")
        // The new user queues its own property while the handed-over batch is
        // still on the wire.
        graph.propertiesManager.setCustomUserProperty(key: "new_user_key", value: "2")
        await slowRequest.open()
        await pollUntil { !self.sentPropertyUserIds(graph.processor).isEmpty }

        XCTAssertEqual(
            sentPropertyUserIds(graph.processor),
            [oldUid],
            "the handed-over batch is delivered under the user that queued it, after the switch"
        )
        XCTAssertEqual(
            sentPropertyKeys(graph.processor, at: 0),
            ["old_user_key"],
            "the post carries the snapshot it was handed — the new user's property cannot leak into it"
        )
        XCTAssertEqual(graph.propertiesUserManager.obtainUserCallsCount, 0, "the post does not go through the user gate")
    }
}
