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
}
