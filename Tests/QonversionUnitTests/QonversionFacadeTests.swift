//
//  QonversionFacadeTests.swift
//  QonversionUnitTests
//
//  Fixation tests for the Qonversion public facade in the UNINITIALIZED state.
//
//  IMPORTANT: Qonversion.initialize(with:) must NEVER be called anywhere in the test
//  process — Qonversion.shared is a process-wide singleton, and these tests fixate the
//  guard behavior of the facade while all internal managers are nil.
//

import XCTest
@testable import Qonversion

final class QonversionFacadeTests: XCTestCase {

    // MARK: - Helpers

    private func assertThrowsInitializationError(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected QonversionError.initializationError to be thrown", file: file, line: line)
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .sdkInitializationError, file: file, line: line)
            XCTAssertEqual(error.message, QonversionErrorType.sdkInitializationError.message(), file: file, line: line)
            XCTAssertNil(error.error, file: file, line: line)
            XCTAssertNil(error.additionalInfo, file: file, line: line)
        } catch {
            XCTFail("Unexpected error type: \(error)", file: file, line: line)
        }
    }

    // MARK: - Silent no-ops when uninitialized

    func testForceSendPropertiesIsANoOpWhenUninitialized() async {
        await Qonversion.shared.forceSendProperties()
    }

    func testIsFallbackFileAccessibleIsFalseWhenUninitialized() {
        XCTAssertFalse(Qonversion.shared.isFallbackFileAccessible())
    }

    // MARK: - Async methods throw initialization error when uninitialized

    func testUserPropertiesThrowsInitializationError() async {
        await assertThrowsInitializationError {
            _ = try await Qonversion.shared.userProperties()
        }
    }

    func testRemoteConfigWithDefaultContextKeyThrowsInitializationError() async {
        await assertThrowsInitializationError {
            _ = try await Qonversion.shared.remoteConfig()
        }
    }

    func testRemoteConfigWithContextKeyThrowsInitializationError() async {
        await assertThrowsInitializationError {
            _ = try await Qonversion.shared.remoteConfig(contextKey: "main")
        }
    }

    func testRemoteConfigListThrowsInitializationError() async {
        await assertThrowsInitializationError {
            _ = try await Qonversion.shared.remoteConfigList()
        }
    }

    func testRemoteConfigListWithContextKeysThrowsInitializationError() async {
        await assertThrowsInitializationError {
            _ = try await Qonversion.shared.remoteConfigList(contextKeys: ["a", "b"], includeEmptyContextKey: true)
        }
    }

    func testAttachUserToRemoteConfigurationThrowsInitializationError() async {
        await assertThrowsInitializationError {
            try await Qonversion.shared.attachUserToRemoteConfiguration(id: "rc-id")
        }
    }

    func testDetachUserFromRemoteConfigurationThrowsInitializationError() async {
        await assertThrowsInitializationError {
            try await Qonversion.shared.detachUserFromRemoteConfiguration(id: "rc-id")
        }
    }

    func testAttachUserToExperimentThrowsInitializationError() async {
        await assertThrowsInitializationError {
            try await Qonversion.shared.attachUserToExperiment(id: "exp-id", groupId: "group-id")
        }
    }

    func testDetachUserFromExperimentThrowsInitializationError() async {
        await assertThrowsInitializationError {
            try await Qonversion.shared.detachUserFromExperiment(id: "exp-id")
        }
    }

    // MARK: - Sync methods are silent no-ops when uninitialized

    // Fixates current behavior: before initialize() the sync facade methods silently do
    // nothing — no crash, no error, no feedback to the caller.
    func testSyncMethodsAreNoOpsWhenUninitialized() {
        Qonversion.shared.collectAppleSearchAdsAttribution()
        Qonversion.shared.collectAdvertisingId()
        Qonversion.shared.setUserProperty(key: .email, value: "test@qonversion.io")
        Qonversion.shared.setUserProperty(key: .custom, value: "value")
        Qonversion.shared.setCustomUserProperty(key: "custom_key", value: "value")
    }

    // MARK: - purchases guards

    func testProductsThrowsInitializationErrorBeforeInitialize() async {
        do {
            _ = try await Qonversion.shared.products()
            XCTFail("Expected initialization error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .sdkInitializationError)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPurchaseThrowsInitializationErrorBeforeInitialize() async {
        do {
            _ = try await Qonversion.shared.purchase(Qonversion.Product(qonversionId: "p", storeId: "s"))
            XCTFail("Expected initialization error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .sdkInitializationError)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCheckEntitlementsThrowsInitializationErrorBeforeInitialize() async {
        do {
            _ = try await Qonversion.shared.checkEntitlements()
            XCTFail("Expected initialization error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .sdkInitializationError)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - assembly graph

    func testAssemblySharesTheProductsManagerInstance() {
        // The entitlements manager consumes the products manager's IN-MEMORY
        // caches (loaded products, mapping) for the local entitlements
        // calculation — a second instance would see empty memory and silently
        // degrade the fallback to cached-entitlements-only.
        let assembly = QonversionAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated())

        let first = assembly.productsManager() as AnyObject
        let second = assembly.productsManager() as AnyObject

        XCTAssertTrue(first === second)
    }

    func testAssemblySharesTheRemoteConfigManagerInstance() {
        // The remote config manager holds the in-memory per-context-key cache —
        // a fresh instance per call would make that cache useless.
        let assembly = QonversionAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated())

        let first = assembly.remoteConfigManager() as AnyObject
        let second = assembly.remoteConfigManager() as AnyObject

        XCTAssertTrue(first === second)
    }

    func testAssemblySharesThePurchasesManagerInstance() {
        // The purchases manager holds the transaction reports dedup gate and
        // the update streams — a second instance would split them.
        let assembly = QonversionAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated())

        let first = assembly.purchasesManager() as AnyObject
        let second = assembly.purchasesManager() as AnyObject

        XCTAssertTrue(first === second)
    }

    func testAssemblySharesTheStoreKitFacadeAndItsDelegateIsThePurchasesManager() {
        // One facade SDK-wide: a single loaded-products cache and a single
        // delegate — the purchases manager, which consumes observed
        // transactions and promo intents.
        let assembly = QonversionAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated())

        let purchasesManager = assembly.purchasesManager()
        _ = assembly.productsManager()

        let facade = assembly.servicesAssembly.storeKitFacade()
        XCTAssertTrue(facade === assembly.servicesAssembly.storeKitFacade())
        XCTAssertTrue(facade.delegate === (purchasesManager as? PurchasesManager))
    }

    func testUserSwitchClearsUserScopedCachesAcrossAssembly() async {
        // End-to-end wiring: the user gate must reach the caches created by
        // the assembly, no matter the creation order.
        let assembly = QonversionAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated())
        guard let productsManager = assembly.productsManager() as? ProductsManager,
              let userManager = assembly.userManager() as? UserManager else {
            return XCTFail("Unexpected assembly types")
        }
        productsManager.loadedProducts = [Qonversion.Product(qonversionId: "q", storeId: "s")]

        // Move away from the original anonymous user first — a logout on the
        // original user is deliberately a no-op.
        try? await userManager.switchToUser(with: "QON_switched_uid")

        XCTAssertTrue(productsManager.loadedProducts.isEmpty)
    }

    // MARK: - a stream created before its source exists

    func testAStreamCreatedBeforeItsSourceExistsDeliversOnceItAppears() async {
        // The typical SwiftUI order: App.init() starts `for await` on a stream
        // and the app delegate calls initialize() afterwards. Handing that loop
        // an already finished stream ends it before the SDK exists, and every
        // purchase after that is lost with nothing to notice it by.
        let sdkIsInitialized = FacadeAsyncGate()
        let received = ReceivedValues()
        var sourceContinuation: AsyncStream<Int>.Continuation?
        let source = AsyncStream<Int> { sourceContinuation = $0 }

        let stream: AsyncStream<Int> = awaitingStream {
            await sdkIsInitialized.wait()

            return source
        }
        let consumer = Task {
            for await value in stream {
                await received.append(value)
            }
        }

        // Before the source exists the loop must simply be waiting, not over.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let beforeInitialize: [Int] = await received.values
        XCTAssertTrue(beforeInitialize.isEmpty)

        await sdkIsInitialized.open()
        sourceContinuation?.yield(7)
        await waitUntil { await !received.values.isEmpty }

        let afterInitialize: [Int] = await received.values
        XCTAssertEqual(afterInitialize, [7], "the loop started before initialize must receive what came after it")

        sourceContinuation?.finish()
        _ = await consumer.value
    }

    func testTheStreamGettersDoNotFinishBeforeInitialize() async {
        // The uninitialized singleton: reading the streams must not hand back
        // an already finished one. Nothing is delivered here — initialize() is
        // never called in this process — so the assertion is that the loop is
        // still waiting when the deadline passes.
        let received = ReceivedValues()
        let consumer = Task {
            for await _ in Qonversion.shared.deferredPurchases {
                await received.append(1)
            }
            await received.append(-1)
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        let values: [Int] = await received.values

        XCTAssertTrue(values.isEmpty, "a finished stream would have appended its terminator")
        consumer.cancel()
    }

    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

/// Collects what a stream delivered.
private actor ReceivedValues {

    private(set) var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }
}

/// wait() suspends until open() is called.
private actor FacadeAsyncGate {

    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

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
