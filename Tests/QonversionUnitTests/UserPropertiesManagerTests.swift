//
//  UserPropertiesManagerTests.swift
//  QonversionUnitTests
//
//  Fixation tests for UserPropertiesManager: lock in the current behavior as-is.
//

import XCTest
@testable import Qonversion

final class UserPropertiesManagerTests: XCTestCase {

    private var requestProcessor: MockRequestProcessor!
    private var propertiesStorage: UserPropertiesStorage!
    private var manager: UserPropertiesManager!

    override func setUp() {
        super.setUp()
        requestProcessor = MockRequestProcessor()
        propertiesStorage = UserPropertiesStorage()
        manager = UserPropertiesManager(
            requestProcessor: requestProcessor,
            propertiesStorage: propertiesStorage,
            delayCalculator: IncrementalDelayCalculator(),
            userIdProvider: InternalConfig(userId: "test-user-id"),
            logger: LoggerWrapper()
        )
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

    // MARK: - userProperties

    func testUserPropertiesReturnsPropertiesFromProcessor() async throws {
        let properties: [Qonversion.UserProperty] = [
            Qonversion.UserProperty(key: "_q_email", value: "test@qonversion.io"),
            Qonversion.UserProperty(key: "custom_key", value: "custom_value"),
        ]
        requestProcessor.results = [properties]

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
    func testUserPropertiesReturnsEmptyResultOnProcessorError() async throws {
        requestProcessor.error = MockError.stubbed

        let result = try await manager.userProperties()

        XCTAssertTrue(result.properties.isEmpty)
        XCTAssertTrue(result.flatPropertiesMap.isEmpty)
    }

    // MARK: - collectAppleSearchAdsAttribution

    // Smoke test only: AdServices attribution token retrieval is unavailable/unentitled
    // in the unit test environment, so we just verify the call does not crash.
    func testCollectAppleSearchAdsAttributionDoesNotCrash() {
        manager.collectAppleSearchAdsAttribution()
    }
}
