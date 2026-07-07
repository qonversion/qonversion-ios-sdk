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
        Qonversion.shared.setUserProperty("test@qonversion.io", key: .email)
        Qonversion.shared.setUserProperty("value", key: .custom)
        Qonversion.shared.setCustomUserProperty("value", key: "custom_key")
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
            _ = try await Qonversion.shared.purchase(Qonversion.Product(qonversionId: "p", storeId: "s", offeringId: nil))
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

    func testLogoutClearsUserScopedCachesAcrossAssembly() async {
        // End-to-end wiring: the user gate must reach the caches created by
        // the assembly, no matter the creation order.
        let assembly = QonversionAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated())
        guard let productsManager = assembly.productsManager() as? ProductsManager,
              let userManager = assembly.userManager() as? UserManager else {
            return XCTFail("Unexpected assembly types")
        }
        productsManager.loadedProducts = [Qonversion.Product(qonversionId: "q", storeId: "s", offeringId: nil)]

        await userManager.logout()

        XCTAssertTrue(productsManager.loadedProducts.isEmpty)
    }
}
