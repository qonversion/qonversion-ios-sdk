//
//  RemoteConfigManagerTests.swift
//  QonversionUnitTests
//
//  Fixation tests for RemoteConfigManager: lock in the current behavior as-is.
//

import XCTest
@testable import Qonversion

final class RemoteConfigManagerTests: XCTestCase {

    private var remoteConfigService: MockRemoteConfigService!
    private var userManager: MockUserManager!
    private var userPropertiesManager: MockUserPropertiesManager!
    private var fallbackService: MockFallbackService!
    private var manager: RemoteConfigManager!

    override func setUp() {
        super.setUp()
        remoteConfigService = MockRemoteConfigService()
        userManager = MockUserManager()
        userManager.user = Qonversion.User(id: "user_abc")
        userPropertiesManager = MockUserPropertiesManager()
        fallbackService = MockFallbackService()
        manager = RemoteConfigManager(
            remoteConfigService: remoteConfigService,
            userManager: userManager,
            userPropertiesManager: userPropertiesManager,
            fallbackService: fallbackService,
            logger: LoggerWrapper()
        )
    }

    override func tearDown() {
        manager = nil
        fallbackService = nil
        userPropertiesManager = nil
        userManager = nil
        remoteConfigService = nil
        super.tearDown()
    }

    private func stubFallbackConfigs() {
        let configs: [Qonversion.RemoteConfig] = [
            makeRemoteConfig(contextKey: "main", identifier: "fallback-main"),
            makeRemoteConfig(contextKey: nil, identifier: "fallback-empty"),
        ]
        fallbackService.fallbackData = FallbackData(products: nil, productsPermissions: nil, remoteConfigs: configs)
    }

    private func retriableError() -> QonversionError {
        let transportError = URLError(.notConnectedToInternet)
        return QonversionError(type: .loadingRemoteConfigFailed, message: nil, error: transportError)
    }

    // MARK: - Helpers

    private func makeRemoteConfig(contextKey: String?, identifier: String = "source-id") -> Qonversion.RemoteConfig {
        let source = Qonversion.RemoteConfig.Source(
            identifier: identifier,
            name: "source-name",
            type: .remoteConfiguration,
            assignmentType: .auto,
            contextKey: contextKey
        )
        return Qonversion.RemoteConfig(payload: ["flag": "on"], experiment: nil, source: source)
    }

    // MARK: - bundled fallback file (production parity)

    func testRetriableLoadFailureFallsBackToTheBundledConfig() async throws {
        remoteConfigService.error = retriableError()
        stubFallbackConfigs()

        let config = try await manager.loadRemoteConfig(contextKey: "main")

        XCTAssertEqual(config.source.identifier, "fallback-main")
    }

    func testFallbackMatchesTheEmptyContextKey() async throws {
        remoteConfigService.error = retriableError()
        stubFallbackConfigs()

        let config = try await manager.loadRemoteConfig(contextKey: nil)

        XCTAssertEqual(config.source.identifier, "fallback-empty")
    }

    func testNonRetriableLoadFailureIgnoresTheFallbackFile() async {
        remoteConfigService.error = MockError.stubbed
        stubFallbackConfigs()

        do {
            _ = try await manager.loadRemoteConfig(contextKey: "main")
            XCTFail("Expected the original error")
        } catch {
            XCTAssertEqual(error as? MockError, .stubbed)
        }
    }

    func testRetriableFailureWithoutTheFileRethrows() async {
        remoteConfigService.error = retriableError()

        do {
            _ = try await manager.loadRemoteConfig(contextKey: "main")
            XCTFail("Expected the original error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .loadingRemoteConfigFailed)
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    func testOfflineUserGateFallsBackToTheBundledConfig() async throws {
        // The first launch without a network connection: even the user
        // creation fails, yet the bundled config must answer.
        userManager.error = QonversionError(type: .userCreationFailed, message: nil, error: URLError(.notConnectedToInternet))
        stubFallbackConfigs()

        let config = try await manager.loadRemoteConfig(contextKey: "main")

        XCTAssertEqual(config.source.identifier, "fallback-main")
    }

    func testListLoadFailureFallsBackToAllBundledConfigs() async throws {
        remoteConfigService.error = retriableError()
        stubFallbackConfigs()

        let list = try await manager.loadRemoteConfigList()

        XCTAssertEqual(list.remoteConfigs.map { $0.source.identifier }, ["fallback-main", "fallback-empty"])
    }

    func testListWithContextKeysFallsBackFiltered() async throws {
        remoteConfigService.error = retriableError()
        stubFallbackConfigs()

        let withEmpty = try await manager.loadRemoteConfigList(contextKeys: ["main"], includeEmptyContextKey: true)
        let withoutEmpty = try await manager.loadRemoteConfigList(contextKeys: ["main"], includeEmptyContextKey: false)

        XCTAssertEqual(withEmpty.remoteConfigs.map { $0.source.identifier }, ["fallback-main", "fallback-empty"])
        XCTAssertEqual(withoutEmpty.remoteConfigs.map { $0.source.identifier }, ["fallback-main"])
    }

    // MARK: - user gate and properties flush (production parity)

    func testLoadWaitsForTheUserGateAndFlushesPropertiesFirst() async throws {
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "main")

        _ = try await manager.loadRemoteConfig(contextKey: "main")

        XCTAssertEqual(userManager.obtainUserCallsCount, 1)
        XCTAssertEqual(userPropertiesManager.sendPropertiesCallsCount, 1,
                       "pending properties must reach the backend before the config is computed")
    }

    func testLoadListFlushesPropertiesFirst() async throws {
        remoteConfigService.remoteConfigListResult = Qonversion.RemoteConfigList(remoteConfigs: [])

        _ = try await manager.loadRemoteConfigList()

        XCTAssertEqual(userManager.obtainUserCallsCount, 1)
        XCTAssertEqual(userPropertiesManager.sendPropertiesCallsCount, 1)
    }

    func testUserGateErrorFailsTheLoadWithoutServiceCall() async {
        userManager.error = MockError.stubbed

        do {
            _ = try await manager.loadRemoteConfig(contextKey: "main")
            XCTFail("Expected the user gate error to propagate")
        } catch {
            XCTAssertEqual(error as? MockError, .stubbed)
        }
        XCTAssertTrue(remoteConfigService.loadRemoteConfigContextKeys.isEmpty)
    }

    func testPropertiesFlushFailureDoesNotBlockTheLoad() async throws {
        userPropertiesManager.error = MockError.stubbed
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "main")

        let config = try await manager.loadRemoteConfig(contextKey: "main")

        XCTAssertEqual(config.source.contextKey, "main")
    }

    func testCachedLoadSkipsTheGateAndTheFlush() async throws {
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "main")
        _ = try await manager.loadRemoteConfig(contextKey: "main")

        _ = try await manager.loadRemoteConfig(contextKey: "main")

        XCTAssertEqual(userManager.obtainUserCallsCount, 1)
        XCTAssertEqual(userPropertiesManager.sendPropertiesCallsCount, 1)
    }

    func testPropertiesFlushHappensStrictlyBeforeTheConfigRequest() async throws {
        let order = OrderRecorder()
        userPropertiesManager.onSendProperties = { await order.record("flush") }
        remoteConfigService.onLoadRemoteConfig = { await order.record("load") }
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "main")

        _ = try await manager.loadRemoteConfig(contextKey: "main")

        let events: [String] = await order.events
        XCTAssertEqual(events, ["flush", "load"])
    }

    func testLoadListWithContextKeysFlushesPropertiesFirst() async throws {
        remoteConfigService.remoteConfigListResult = Qonversion.RemoteConfigList(remoteConfigs: [
            makeRemoteConfig(contextKey: "a"),
        ])

        _ = try await manager.loadRemoteConfigList(contextKeys: ["a"], includeEmptyContextKey: false)

        XCTAssertEqual(userManager.obtainUserCallsCount, 1)
        XCTAssertEqual(userPropertiesManager.sendPropertiesCallsCount, 1)
    }

    func testAttachAndDetachWaitForTheUserGate() async {
        userManager.error = MockError.stubbed

        let operations: [() async throws -> Void] = [
            { try await self.manager.attachUserToRemoteConfig(id: "rc") },
            { try await self.manager.detachUserFromRemoteConfig(id: "rc") },
            { try await self.manager.attachUserToExperiment(id: "exp", groupId: "g") },
            { try await self.manager.detachUserFromExperiment(id: "exp") },
        ]
        for operation in operations {
            do {
                try await operation()
                XCTFail("Expected the user gate error to propagate")
            } catch {
                XCTAssertEqual(error as? MockError, .stubbed)
            }
        }
        XCTAssertTrue(remoteConfigService.attachedRemoteConfigIds.isEmpty)
        XCTAssertTrue(remoteConfigService.detachedRemoteConfigIds.isEmpty)
        XCTAssertTrue(remoteConfigService.attachedExperiments.isEmpty)
        XCTAssertTrue(remoteConfigService.detachedExperimentIds.isEmpty)
    }

    // MARK: - loadRemoteConfig caching

    func testLoadRemoteConfigCachesResultByContextKey() async throws {
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "main")

        let first = try await manager.loadRemoteConfig(contextKey: "main")
        let second = try await manager.loadRemoteConfig(contextKey: "main")

        XCTAssertEqual(remoteConfigService.loadRemoteConfigContextKeys.count, 1)
        XCTAssertEqual(remoteConfigService.loadRemoteConfigContextKeys.first, "main")
        XCTAssertEqual(first.source.identifier, "source-id")
        XCTAssertEqual(second.source.identifier, "source-id")
    }

    func testLoadRemoteConfigCachesNilContextKeyUnderEmptyKey() async throws {
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: nil)

        _ = try await manager.loadRemoteConfig(contextKey: nil)
        _ = try await manager.loadRemoteConfig(contextKey: nil)

        XCTAssertEqual(remoteConfigService.loadRemoteConfigContextKeys.count, 1)
        XCTAssertNil(remoteConfigService.loadRemoteConfigContextKeys.first ?? nil)
    }

    func testLoadRemoteConfigHitsServiceForEachNewContextKey() async throws {
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "a")

        _ = try await manager.loadRemoteConfig(contextKey: "a")
        _ = try await manager.loadRemoteConfig(contextKey: "b")

        XCTAssertEqual(remoteConfigService.loadRemoteConfigContextKeys.count, 2)
        XCTAssertEqual(remoteConfigService.loadRemoteConfigContextKeys[0], "a")
        XCTAssertEqual(remoteConfigService.loadRemoteConfigContextKeys[1], "b")
    }

    func testLoadRemoteConfigErrorIsNotCached() async throws {
        remoteConfigService.error = MockError.stubbed

        do {
            _ = try await manager.loadRemoteConfig(contextKey: "main")
            XCTFail("Expected loadRemoteConfig to rethrow the service error")
        } catch {
            XCTAssertEqual(error as? MockError, .stubbed)
        }

        remoteConfigService.error = nil
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "main")

        _ = try await manager.loadRemoteConfig(contextKey: "main")

        XCTAssertEqual(remoteConfigService.loadRemoteConfigContextKeys.count, 2)
    }

    // MARK: - loadRemoteConfigList

    func testLoadRemoteConfigListForwardsAndPopulatesCache() async throws {
        remoteConfigService.remoteConfigListResult = Qonversion.RemoteConfigList(remoteConfigs: [
            makeRemoteConfig(contextKey: "a", identifier: "id-a"),
            makeRemoteConfig(contextKey: nil, identifier: "id-empty"),
        ])

        let list = try await manager.loadRemoteConfigList()

        XCTAssertEqual(remoteConfigService.loadListCallsCount, 1)
        XCTAssertEqual(list.remoteConfigs.map { $0.source.identifier }, ["id-a", "id-empty"])

        // Loaded list entries are cached by their source contextKey (nil -> ""), so
        // subsequent single loads do not hit the service at all.
        let cachedA = try await manager.loadRemoteConfig(contextKey: "a")
        let cachedEmpty = try await manager.loadRemoteConfig(contextKey: nil)

        XCTAssertTrue(remoteConfigService.loadRemoteConfigContextKeys.isEmpty)
        XCTAssertEqual(cachedA.source.identifier, "id-a")
        XCTAssertEqual(cachedEmpty.source.identifier, "id-empty")
    }

    // Fixates current behavior: when every requested context key is already cached, the
    // list is built from the cache and includeEmptyContextKey is silently ignored —
    // the empty-context-key config is NOT included and the service is not called.
    func testLoadRemoteConfigListWithContextKeysReturnsCachedWhenAllKeysCached() async throws {
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "a", identifier: "id-a")
        _ = try await manager.loadRemoteConfig(contextKey: "a")
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "b", identifier: "id-b")
        _ = try await manager.loadRemoteConfig(contextKey: "b")

        let list = try await manager.loadRemoteConfigList(contextKeys: ["a", "b"], includeEmptyContextKey: true)

        XCTAssertTrue(remoteConfigService.loadListContextKeysArgs.isEmpty)
        XCTAssertEqual(list.remoteConfigs.map { $0.source.identifier }, ["id-a", "id-b"])
        XCTAssertNil(list.remoteConfigForEmptyContextKey())
    }

    func testLoadRemoteConfigListWithContextKeysForwardsToServiceWhenNotFullyCached() async throws {
        remoteConfigService.remoteConfigListResult = Qonversion.RemoteConfigList(remoteConfigs: [
            makeRemoteConfig(contextKey: "a", identifier: "id-a"),
            makeRemoteConfig(contextKey: "b", identifier: "id-b"),
        ])

        let list = try await manager.loadRemoteConfigList(contextKeys: ["a", "b"], includeEmptyContextKey: false)

        XCTAssertEqual(remoteConfigService.loadListContextKeysArgs.count, 1)
        XCTAssertEqual(remoteConfigService.loadListContextKeysArgs.first?.contextKeys, ["a", "b"])
        XCTAssertEqual(remoteConfigService.loadListContextKeysArgs.first?.includeEmpty, false)
        XCTAssertEqual(list.remoteConfigs.count, 2)

        // The loaded list populates the cache for subsequent single loads.
        _ = try await manager.loadRemoteConfig(contextKey: "a")
        XCTAssertTrue(remoteConfigService.loadRemoteConfigContextKeys.isEmpty)
    }

    func testLoadRemoteConfigListErrorPropagates() async {
        remoteConfigService.error = MockError.stubbed

        do {
            _ = try await manager.loadRemoteConfigList()
            XCTFail("Expected loadRemoteConfigList to rethrow the service error")
        } catch {
            XCTAssertEqual(error as? MockError, .stubbed)
        }
    }

    // MARK: - Attach / detach pass-through

    func testAttachDetachMethodsForwardArgumentsToService() async throws {
        try await manager.attachUserToRemoteConfig(id: "rc-1")
        try await manager.detachUserFromRemoteConfig(id: "rc-2")
        try await manager.attachUserToExperiment(id: "exp-1", groupId: "group-1")
        try await manager.detachUserFromExperiment(id: "exp-2")

        XCTAssertEqual(remoteConfigService.attachedRemoteConfigIds, ["rc-1"])
        XCTAssertEqual(remoteConfigService.detachedRemoteConfigIds, ["rc-2"])
        XCTAssertEqual(remoteConfigService.attachedExperiments.count, 1)
        XCTAssertEqual(remoteConfigService.attachedExperiments.first?.id, "exp-1")
        XCTAssertEqual(remoteConfigService.attachedExperiments.first?.groupId, "group-1")
        XCTAssertEqual(remoteConfigService.detachedExperimentIds, ["exp-2"])
    }

    // MARK: - User change

    func testResponseForThePreviousUserIsNotCachedAfterUserChange() async throws {
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "main", identifier: "old-user-config")
        let gate = ManagerAsyncGate()
        remoteConfigService.onLoadRemoteConfig = { await gate.wait() }

        // The load starts for the previous user and resolves after the switch.
        async let staleLoad = manager.loadRemoteConfig(contextKey: "main")
        try? await Task.sleep(nanoseconds: 50_000_000)
        manager.userDidChange()
        await gate.open()
        _ = try await staleLoad

        // The next load must hit the service, not the stale cache.
        remoteConfigService.onLoadRemoteConfig = nil
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "main", identifier: "new-user-config")
        let fresh = try await manager.loadRemoteConfig(contextKey: "main")

        XCTAssertEqual(fresh.source.identifier, "new-user-config")
        XCTAssertEqual(remoteConfigService.loadRemoteConfigContextKeys.count, 2)
    }

    func testUserDidChangeClearsCachedConfigs() async throws {
        remoteConfigService.remoteConfigResult = makeRemoteConfig(contextKey: "main")
        _ = try await manager.loadRemoteConfig(contextKey: "main")

        manager.userDidChange()

        _ = try await manager.loadRemoteConfig(contextKey: "main")
        XCTAssertEqual(remoteConfigService.loadRemoteConfigContextKeys.count, 2, "the new user must not see the previous user's configs")
    }

    func testAttachDetachMethodsPropagateServiceErrors() async {
        remoteConfigService.error = MockError.stubbed

        let operations: [(String, () async throws -> Void)] = [
            ("attachUserToRemoteConfig", { try await self.manager.attachUserToRemoteConfig(id: "rc") }),
            ("detachUserFromRemoteConfig", { try await self.manager.detachUserFromRemoteConfig(id: "rc") }),
            ("attachUserToExperiment", { try await self.manager.attachUserToExperiment(id: "exp", groupId: "group") }),
            ("detachUserFromExperiment", { try await self.manager.detachUserFromExperiment(id: "exp") }),
        ]

        for (name, operation) in operations {
            do {
                try await operation()
                XCTFail("Expected \(name) to rethrow the service error")
            } catch {
                XCTAssertEqual(error as? MockError, .stubbed, "Unexpected error from \(name)")
            }
        }
    }
}

/// A reusable async gate: wait() suspends until open() is called.
private actor ManagerGateStorage {
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

private final class ManagerAsyncGate: @unchecked Sendable {
    private let storage = ManagerGateStorage()
    func open() async { await storage.open() }
    func wait() async { await storage.wait() }
}

/// Records event ordering across concurrent async hooks.
private actor OrderRecorder {
    var events: [String] = []
    func record(_ event: String) { events.append(event) }
}
