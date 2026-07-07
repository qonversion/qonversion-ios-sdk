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

    // MARK: - legacy uid migration (installs updated from the previous production SDK)

    func testInitMigratesLegacyUidToNewStorage() {
        let storage = makeStorage()
        storage.set(string: "QON_legacy_uid", forKey: "com.qonversion.keys.storedUserID")
        let config = InternalConfig(userId: "")

        _ = UserService(requestProcessor: MockRequestProcessor(), localStorage: storage, internalConfig: config)

        XCTAssertEqual(config.userId, "QON_legacy_uid")
        XCTAssertEqual(storage.string(forKey: userIdKey), "QON_legacy_uid")
        XCTAssertNil(storage.string(forKey: "com.qonversion.keys.storedUserID"), "the legacy storage must be cleaned after migration")
    }

    func testInitPrefersLegacyUidOverNewStorage() {
        let storage = makeStorage()
        storage.set(string: "QON_legacy_uid", forKey: "com.qonversion.keys.storedUserID")
        storage.set(string: "QON_new_uid", forKey: userIdKey)
        let config = InternalConfig(userId: "")

        _ = UserService(requestProcessor: MockRequestProcessor(), localStorage: storage, internalConfig: config)

        XCTAssertEqual(config.userId, "QON_legacy_uid")
        XCTAssertEqual(storage.string(forKey: userIdKey), "QON_legacy_uid")
        XCTAssertNil(storage.string(forKey: "com.qonversion.keys.storedUserID"))
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

    func testCreateUserUsesCurrentUidAndSendsCreateUserRequest() async throws {
        let processor = MockRequestProcessor()
        let storage = makeStorage()
        let config = InternalConfig(userId: "initial")
        let service = UserService(requestProcessor: processor, localStorage: storage, internalConfig: config)
        let idAfterInit = config.userId

        let stubUser = try decodeUserStub()
        processor.results = [stubUser]

        let user = try await service.createUser()

        // The backend upserts by uid, so createUser keeps the current uid:
        // a migrated install gets its existing user back instead of a new one.
        let idAfterCreate = config.userId
        XCTAssertEqual(idAfterInit, idAfterCreate)
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

    func testCreateUserGeneratesUidWhenCurrentIsEmpty() async throws {
        let processor = MockRequestProcessor()
        let storage = makeStorage()
        let config = InternalConfig(userId: "")
        let service = UserService(requestProcessor: processor, localStorage: storage, internalConfig: config)
        config.userId = ""
        storage.removeObject(forKey: userIdKey)

        processor.results = [try decodeUserStub()]

        _ = try await service.createUser()

        XCTAssertTrue(config.userId.hasPrefix("QON_"))
        XCTAssertEqual(storage.string(forKey: userIdKey), config.userId)
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

    // MARK: - identity

    private func decodeIdentityStub(id: String, userId: String?) throws -> Qonversion.Identity {
        let userIdJson = userId.map { "\"\($0)\"" } ?? "null"
        let json = "{\"id\": \"\(id)\", \"user_id\": \(userIdJson)}"
        return try JSONDecoder().decode(Qonversion.Identity.self, from: Data(json.utf8))
    }

    func testIdentitySendsGetIdentityRequestAndReturnsLinkedUid() async throws {
        let processor = MockRequestProcessor()
        let service = UserService(requestProcessor: processor, localStorage: makeStorage(), internalConfig: InternalConfig(userId: "QON_a"))
        processor.results = [try decodeIdentityStub(id: "ext_1", userId: "QON_linked")]

        let linkedUid = try await service.identity(for: "ext_1")

        XCTAssertEqual(processor.processedRequests, [Request.getIdentity(externalId: "ext_1")])
        XCTAssertEqual(linkedUid, "QON_linked")
    }

    func testIdentityMapsNotFoundToNil() async throws {
        let processor = MockRequestProcessor()
        let service = UserService(requestProcessor: processor, localStorage: makeStorage(), internalConfig: InternalConfig(userId: "QON_a"))
        processor.error = QonversionError(type: .unknown, additionalInfo: ["statusCode": 404])

        let linkedUid = try await service.identity(for: "ext_1")

        XCTAssertNil(linkedUid, "backend 404 means the identity is not linked yet")
    }

    func testIdentityWrapsOtherErrorsIntoIdentityLoadingFailed() async {
        let processor = MockRequestProcessor()
        let service = UserService(requestProcessor: processor, localStorage: makeStorage(), internalConfig: InternalConfig(userId: "QON_a"))
        processor.error = QonversionError(type: .internal, additionalInfo: ["statusCode": 500])

        do {
            _ = try await service.identity(for: "ext_1")
            XCTFail("Expected identity(for:) to throw")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .identityLoadingFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCreateIdentitySendsPostWithUserIdBody() async throws {
        let processor = MockRequestProcessor()
        let service = UserService(requestProcessor: processor, localStorage: makeStorage(), internalConfig: InternalConfig(userId: "QON_a"))
        processor.results = [try decodeIdentityStub(id: "ext_1", userId: "QON_a")]

        let resultUid = try await service.createIdentity(externalId: "ext_1", userId: "QON_a")

        XCTAssertEqual(processor.processedRequests, [Request.createIdentity(externalId: "ext_1", body: ["user_id": "QON_a"])])
        XCTAssertEqual(resultUid, "QON_a")
    }

    func testCreateIdentityWrapsErrorsIntoIdentityCreationFailed() async {
        let processor = MockRequestProcessor()
        let service = UserService(requestProcessor: processor, localStorage: makeStorage(), internalConfig: InternalConfig(userId: "QON_a"))
        processor.error = MockError.stubbed

        do {
            _ = try await service.createIdentity(externalId: "ext_1", userId: "QON_a")
            XCTFail("Expected createIdentity to throw")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .identityCreationFailed)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
