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
    private let originalUserIdKey = "qonversion.keys.originalUserId"
    private let legacyUserIdKey = "com.qonversion.keys.storedUserID"
    private let legacyOriginalUserIdKey = "com.qonversion.keys.originalUserID"
    /// The dedicated suite the previous production SDK generation persisted into.
    private let legacySuiteName = "qonversion.localstorage.main"
    private var legacyDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        legacyDefaults = UserDefaults(suiteName: legacySuiteName)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
    }

    override func tearDown() {
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        legacyDefaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStorage() -> LocalStorage {
        LocalStorage(userDefaults: TestDefaults.makeIsolated(), encoder: JSONEncoder(), decoder: JSONDecoder())
    }

    private func decodeUserStub(
        id: String = "QON_stub_user",
        createdAt: String = "2024-03-09T16:10:00Z",
        environment: String = "prod"
    ) throws -> Qonversion.User {
        let json = #"{"id": "\#(id)", "created_at": "\#(createdAt)", "environment": "\#(environment)"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
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

    func testFreshInstallRecordsItsUidAsTheOriginal() {
        let storage = makeStorage()
        _ = UserService(requestProcessor: MockRequestProcessor(), localStorage: storage, internalConfig: InternalConfig(userId: ""))

        let uid = storage.string(forKey: UserServiceStorageKeys.userIdKey.rawValue)
        XCTAssertEqual(storage.string(forKey: UserServiceStorageKeys.originalUserIdKey.rawValue), uid,
                       "without the original uid, logout degrades to a permanent no-op")
    }

    func testLegacyMigrationPrefersTheProductionOriginalUidKey() {
        // An install identified in the ObjC SDK: the current uid is the
        // IDENTIFIED user; the true original anonymous uid lives in the
        // production original-user key.
        let storage = makeStorage()
        storage.set(string: "QON_identified", forKey: "com.qonversion.keys.storedUserID")
        storage.set(string: "QON_true_original", forKey: "com.qonversion.keys.originalUserID")

        _ = UserService(requestProcessor: MockRequestProcessor(), localStorage: storage, internalConfig: InternalConfig(userId: ""))

        XCTAssertEqual(storage.string(forKey: UserServiceStorageKeys.userIdKey.rawValue), "QON_identified")
        XCTAssertEqual(storage.string(forKey: UserServiceStorageKeys.originalUserIdKey.rawValue), "QON_true_original")
        XCTAssertNil(storage.string(forKey: "com.qonversion.keys.originalUserID"), "the legacy key is consumed")
    }

    func testInitMigratesLegacyUidFromTheProductionSuite() {
        // The previous SDK generation persisted into its own UserDefaults
        // suite, never into the configured/standard one — reading only the
        // configured storage means the migration never fires and an upgrading
        // install loses its user.
        legacyDefaults.set("QON_suite_uid", forKey: legacyUserIdKey)
        let storage = makeStorage()
        let config = InternalConfig(userId: "")

        _ = UserService(requestProcessor: MockRequestProcessor(), localStorage: storage, internalConfig: config)

        XCTAssertEqual(config.userId, "QON_suite_uid")
        XCTAssertEqual(storage.string(forKey: userIdKey), "QON_suite_uid")
        XCTAssertNil(legacyDefaults.string(forKey: legacyUserIdKey), "the legacy suite must be cleaned after migration")
    }

    func testInitMigratesLegacyOriginalUidFromTheProductionSuite() {
        legacyDefaults.set("QON_suite_identified", forKey: legacyUserIdKey)
        legacyDefaults.set("QON_suite_original", forKey: legacyOriginalUserIdKey)
        let storage = makeStorage()

        _ = UserService(requestProcessor: MockRequestProcessor(), localStorage: storage, internalConfig: InternalConfig(userId: ""))

        XCTAssertEqual(storage.string(forKey: userIdKey), "QON_suite_identified")
        XCTAssertEqual(storage.string(forKey: originalUserIdKey), "QON_suite_original")
        XCTAssertNil(legacyDefaults.string(forKey: legacyOriginalUserIdKey), "the legacy suite key is consumed")
    }

    func testLegacyMigrationWithoutTheOriginalKeyFallsBackToTheMigratedUid() {
        let storage = makeStorage()
        storage.set(string: "QON_legacy", forKey: "com.qonversion.keys.storedUserID")

        _ = UserService(requestProcessor: MockRequestProcessor(), localStorage: storage, internalConfig: InternalConfig(userId: ""))

        XCTAssertEqual(storage.string(forKey: UserServiceStorageKeys.originalUserIdKey.rawValue), "QON_legacy")
    }

    func testUserRequestsCarryTheInitTrigger() async throws {
        let processor = MockRequestProcessor()
        let service = UserService(requestProcessor: processor, localStorage: makeStorage(), internalConfig: InternalConfig(userId: "initial"))
        processor.results = [try decodeUserStub()]

        _ = try await service.createUser()

        XCTAssertEqual(processor.processedTriggers, [.initialization])
    }

    func testCreateUserUsesCurrentUidAndSendsCreateUserRequest() async throws {
        let processor = MockRequestProcessor()
        let storage = makeStorage()
        let config = InternalConfig(userId: "initial")
        let service = UserService(requestProcessor: processor, localStorage: storage, internalConfig: config)
        let idAfterInit = config.userId

        let stubUser = try decodeUserStub()
        processor.results = [stubUser]

        let user = try await service.createUser()

        // createUser posts the CURRENT uid instead of minting a new one — a
        // migrated install must keep the user the previous SDK created.
        let idAfterCreate = config.userId
        XCTAssertEqual(idAfterInit, idAfterCreate)
        XCTAssertEqual(storage.string(forKey: userIdKey), idAfterCreate)

        // The uid is the whole body: the SDK no longer signals a store
        // environment, the backend derives it from the receipt.
        XCTAssertEqual(
            processor.processedRequests,
            [Request.createUser(body: ["id": idAfterCreate])]
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

    // MARK: - createUser: the already_exists conflict

    /// The backend answers a repeated uid with `already_exists` (422). Every
    /// install upgraded from the previous SDK generation posts a uid the
    /// backend already knows, so the conflict must resolve to that user.
    private func alreadyExistsError(nested: Bool = false) -> QonversionError {
        let apiError = QonversionError(
            type: .unknown,
            message: "user already exists",
            error: nil,
            additionalInfo: [ErrorConstants.statusCodeKey.rawValue: 422],
            apiCode: "already_exists",
            apiType: "logical"
        )
        guard nested else { return apiError }

        return QonversionError(type: .internal, message: nil, error: apiError)
    }

    func testCreateUserFetchesTheExistingUserOnAlreadyExists() async throws {
        let processor = MockRequestProcessor()
        let storage = makeStorage()
        storage.set(string: "QON_migrated_uid", forKey: userIdKey)
        let config = InternalConfig(userId: "initial")
        let service = UserService(requestProcessor: processor, localStorage: storage, internalConfig: config)

        let existingUser = try decodeUserStub(id: "QON_migrated_uid", environment: "sandbox")
        processor.results = [alreadyExistsError(), existingUser]

        let user = try await service.createUser()

        XCTAssertEqual(
            processor.processedRequests,
            [Request.createUser(body: ["id": "QON_migrated_uid"]), Request.getUser(id: "QON_migrated_uid")]
        )
        XCTAssertEqual(user.id, "QON_migrated_uid")
        XCTAssertEqual(user.environment, .sandbox)
        XCTAssertEqual(config.userId, "QON_migrated_uid")
    }

    /// The conflict arrives wrapped by whichever layer failed — the whole
    /// error chain has to be inspected, not only its outermost link.
    func testCreateUserFetchesTheExistingUserOnNestedAlreadyExists() async throws {
        let processor = MockRequestProcessor()
        let storage = makeStorage()
        storage.set(string: "QON_migrated_uid", forKey: userIdKey)
        let service = UserService(requestProcessor: processor, localStorage: storage, internalConfig: InternalConfig(userId: "initial"))

        processor.results = [alreadyExistsError(nested: true), try decodeUserStub(id: "QON_migrated_uid")]

        let user = try await service.createUser()

        XCTAssertEqual(processor.processedRequests.count, 2)
        XCTAssertEqual(user.id, "QON_migrated_uid")
    }

    func testCreateUserKeepsFailingOnAnyOtherApiCode() async {
        let processor = MockRequestProcessor()
        let storage = makeStorage()
        storage.set(string: "QON_uid", forKey: userIdKey)
        let service = UserService(requestProcessor: processor, localStorage: storage, internalConfig: InternalConfig(userId: "initial"))

        let otherApiError = QonversionError(type: .invalidRequest, message: nil, error: nil, additionalInfo: nil, apiCode: "invalid_data", apiType: "request")
        processor.results = [otherApiError, try? decodeUserStub(id: "QON_uid")]

        do {
            _ = try await service.createUser()
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .userCreationFailed)
            XCTAssertEqual((error.error as? QonversionError)?.apiCode, "invalid_data")
            // Only the conflict slug recovers: no user fetch was attempted.
            XCTAssertEqual(processor.processedRequests, [Request.createUser(body: ["id": "QON_uid"])])
        } catch {
            XCTFail("Expected QonversionError, got \(error)")
        }
    }

    func testCreateUserSurfacesTheFetchFailureWhenTheConflictRecoveryFails() async {
        let processor = MockRequestProcessor()
        let storage = makeStorage()
        storage.set(string: "QON_uid", forKey: userIdKey)
        let service = UserService(requestProcessor: processor, localStorage: storage, internalConfig: InternalConfig(userId: "initial"))

        processor.results = [alreadyExistsError(), MockError.stubbed]

        do {
            _ = try await service.createUser()
            XCTFail("Expected an error")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .userLoadingFailed)
            XCTAssertEqual(processor.processedRequests.count, 2)
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

        XCTAssertEqual(processor.processedRequests, [Request.createIdentity(body: ["identity_id": "ext_1", "user_id": "QON_a"])])
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
