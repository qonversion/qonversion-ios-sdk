//
//  UserServiceTests.swift
//  QonversionUnitTests
//
//  Fixation tests for UserService: locks in current behavior as-is.
//

import XCTest
@testable import Qonversion

final class UserServiceTests: XCTestCase {

    private let userIdKey = "qonversion.keys.userId"

    // MARK: - Helpers

    private func makeStorage() -> LocalStorage {
        LocalStorage(userDefaults: TestDefaults.makeIsolated(), encoder: JSONEncoder(), decoder: JSONDecoder())
    }

    private func decodeUserStub(
        id: String = "QON_stub_user",
        created: TimeInterval = 1_710_000_000,
        environment: String = "production"
    ) throws -> Qonversion.User {
        let json = #"{"id": "\#(id)", "created": \#(created), "environment": "\#(environment)"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(Qonversion.User.self, from: Data(json.utf8))
    }

    // MARK: - init / prepareUserId

    func testInitUsesPersistedUserIdFromStorage() {
        let storage = makeStorage()
        storage.set(string: "QON_persisted_id", forKey: userIdKey)
        let config = InternalConfig(userId: "initial")

        _ = UserService(requestProcessor: MockRequestProcessor(), localStorage: storage, internalConfig: config)

        XCTAssertEqual(config.userId, "QON_persisted_id")
        // Persisted value is untouched.
        XCTAssertEqual(storage.string(forKey: userIdKey), "QON_persisted_id")
    }

    func testInitGeneratesAndPersistsUserIdWhenStorageIsEmpty() {
        let storage = makeStorage()
        let config = InternalConfig(userId: "initial")

        _ = UserService(requestProcessor: MockRequestProcessor(), localStorage: storage, internalConfig: config)

        XCTAssertNotEqual(config.userId, "initial")
        XCTAssertTrue(config.userId.hasPrefix("QON_"))
        // Generated id is persisted to the storage and set into the config.
        XCTAssertEqual(storage.string(forKey: userIdKey), config.userId)
    }

    // MARK: - generateUserId

    func testGenerateUserIdFormatAndSideEffects() {
        let storage = makeStorage()
        let config = InternalConfig(userId: "initial")
        let service = UserService(requestProcessor: MockRequestProcessor(), localStorage: storage, internalConfig: config)

        let userId = service.generateUserId()

        XCTAssertTrue(userId.hasPrefix("QON_"))
        let suffix = String(userId.dropFirst(4))
        // UUID without dashes, lowercased.
        XCTAssertEqual(suffix.count, 32)
        XCTAssertEqual(suffix, suffix.lowercased())
        XCTAssertFalse(suffix.contains("-"))
        // Persists to storage and updates the config.
        XCTAssertEqual(storage.string(forKey: userIdKey), userId)
        XCTAssertEqual(config.userId, userId)
    }

    func testGenerateUserIdReturnsNewIdOnEveryCall() {
        let storage = makeStorage()
        let config = InternalConfig(userId: "initial")
        let service = UserService(requestProcessor: MockRequestProcessor(), localStorage: storage, internalConfig: config)

        let firstId = service.generateUserId()
        let secondId = service.generateUserId()

        // Fixates current behavior: every call generates a brand new id, overwriting the previous one.
        XCTAssertNotEqual(firstId, secondId)
        XCTAssertEqual(storage.string(forKey: userIdKey), secondId)
        XCTAssertEqual(config.userId, secondId)
    }

    // MARK: - createUser

    func testCreateUserRegeneratesIdAndSendsCreateUserRequest() async throws {
        let processor = MockRequestProcessor()
        let storage = makeStorage()
        let config = InternalConfig(userId: "initial")
        let service = UserService(requestProcessor: processor, localStorage: storage, internalConfig: config)
        let idAfterInit = config.userId

        let stubUser = try decodeUserStub()
        processor.results = [stubUser]

        let user = try await service.createUser()

        // Fixates current behavior: createUser generates a NEW user id, replacing the one created at init.
        let idAfterCreate = config.userId
        XCTAssertNotEqual(idAfterInit, idAfterCreate)
        XCTAssertEqual(storage.string(forKey: userIdKey), idAfterCreate)

        // Fixates current behavior: the environment in the request body is hardcoded to "sandbox".
        XCTAssertEqual(
            processor.processedRequests,
            [Request.createUser(id: idAfterCreate, body: ["environment": "sandbox"])]
        )

        XCTAssertEqual(user.id, stubUser.id)
        XCTAssertEqual(user.creationDate, stubUser.creationDate)
        XCTAssertEqual(user.environment, stubUser.environment)
    }

    func testCreateUserWrapsProcessorErrorIntoUserCreationFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = UserService(requestProcessor: processor, localStorage: makeStorage(), internalConfig: InternalConfig(userId: "initial"))

        do {
            _ = try await service.createUser()
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .userCreationFailed)
            XCTAssertEqual(error.error as? MockError, .stubbed)
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    // MARK: - user

    func testUserSendsGetUserRequestWithConfigUserIdAndReturnsUser() async throws {
        let processor = MockRequestProcessor()
        let storage = makeStorage()
        storage.set(string: "QON_persisted_id", forKey: userIdKey)
        let config = InternalConfig(userId: "initial")
        let service = UserService(requestProcessor: processor, localStorage: storage, internalConfig: config)

        let stubUser = try decodeUserStub(id: "QON_persisted_id", environment: "sandbox")
        processor.results = [stubUser]

        let user = try await service.user()

        XCTAssertEqual(processor.processedRequests, [Request.getUser(id: "QON_persisted_id")])
        XCTAssertEqual(user.id, "QON_persisted_id")
        XCTAssertEqual(user.environment, .sandbox)
    }

    func testUserWrapsProcessorErrorIntoUserLoadingFailed() async {
        let processor = MockRequestProcessor()
        processor.error = MockError.stubbed
        let service = UserService(requestProcessor: processor, localStorage: makeStorage(), internalConfig: InternalConfig(userId: "initial"))

        do {
            _ = try await service.user()
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .userLoadingFailed)
            XCTAssertEqual(error.error as? MockError, .stubbed)
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }
}
