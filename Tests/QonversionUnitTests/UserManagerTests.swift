//
//  UserManagerTests.swift
//  QonversionUnitTests
//
//  Contract tests for the user lifecycle gate (TDD — written before the implementation).
//
//  The gate guarantees:
//  - user is created on the backend at most once (single-flight), no matter how
//    many concurrent callers need it;
//  - on failure the gate resets, so the next data-sending attempt retries creation;
//  - all concurrent callers receive the same user;
//  - when identify is pending, waiters are released only AFTER the identity
//    request has been sent (creation → identity → everyone else).
//

import XCTest
@testable import Qonversion

final class UserManagerTests: XCTestCase {

    private var service: MockUserService!
    private var storage: MockLocalStorage!
    private var config: InternalConfig!
    private var notifier: UserChangesNotifier!
    private var observer: UserChangeObserverSpy!
    private var manager: UserManager!
    private var appTransactionReader: MockAppTransactionReader!

    private let anonUid = "QON_anon_uid"
    private let identifiedUid = "QON_identified_uid"
    private let ownerUid = "QON_owner_uid"
    private let identityStorageKey = "qonversion.keys.identityExternalId"
    private let userStorageKey = "qonversion.keys.user"

    override func setUp() {
        super.setUp()
        service = MockUserService()
        storage = MockLocalStorage()
        config = InternalConfig(userId: anonUid)
        notifier = UserChangesNotifier()
        observer = UserChangeObserverSpy()
        appTransactionReader = MockAppTransactionReader()
        notifier.add(observer: observer)
        storage.set(string: anonUid, forKey: UserServiceStorageKeys.originalUserIdKey.rawValue)
        manager = makeManager()
    }

    override func tearDown() {
        manager = nil
        appTransactionReader = nil
        observer = nil
        notifier = nil
        config = nil
        storage = nil
        service = nil
        super.tearDown()
    }

    private func makeManager() -> UserManager {
        UserManager(userService: service, localStorage: storage, internalConfig: config, userChangesNotifier: notifier, logger: LoggerWrapper(), appTransactionReader: appTransactionReader)
    }

    private func makeUser(id: String, environment: String = "sandbox") throws -> Qonversion.User {
        let json = #"{"id": "\#(id)", "created_at": "2023-11-14T22:13:20Z", "environment": "\#(environment)"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Qonversion.User.self, from: Data(json.utf8))
    }

    /// Polls until the condition is true or the timeout elapses.
    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Creation

    func testObtainUserCreatesUserOnFirstCall() async throws {
        service.createUserResult = try makeUser(id: anonUid)

        let user = try await manager.obtainUser()

        XCTAssertEqual(user.id, anonUid)
        XCTAssertEqual(service.createUserCallsCount, 1)
    }

    func testObtainUserReturnsCachedUserWithoutSecondRequest() async throws {
        service.createUserResult = try makeUser(id: anonUid)

        _ = try await manager.obtainUser()
        let second = try await manager.obtainUser()

        XCTAssertEqual(second.id, anonUid)
        XCTAssertEqual(service.createUserCallsCount, 1)
    }

    func testObtainUserPersistsCreatedUserAcrossInstances() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()

        // A fresh manager over the same storage must not create the user again.
        let secondManager = makeManager()
        let user = try await secondManager.obtainUser()

        XCTAssertEqual(user.id, anonUid)
        XCTAssertEqual(service.createUserCallsCount, 1)
    }

    // MARK: - Single-flight

    func testConcurrentObtainUserCreatesExactlyOneUser() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        // Hold the creation open so all callers pile up on the same in-flight request.
        let gate = AsyncGate()
        service.onCreateUser = { await gate.wait() }

        async let first = manager.obtainUser()
        async let second = manager.obtainUser()
        async let third = manager.obtainUser()
        async let fourth = manager.obtainUser()
        async let fifth = manager.obtainUser()

        await waitUntil { self.service.createUserCallsCount >= 1 }
        await gate.open()

        let users = try await [first, second, third, fourth, fifth]

        XCTAssertEqual(service.createUserCallsCount, 1)
        XCTAssertEqual(Set(users.map(\.id)), [anonUid])
    }

    // MARK: - Failure & retry

    func testObtainUserFailureResetsGateSoNextCallRetries() async throws {
        service.error = MockError.stubbed

        do {
            _ = try await manager.obtainUser()
            XCTFail("Expected obtainUser to rethrow the creation error")
        } catch { }

        // Next demand retries with a NEW request.
        service.error = nil
        service.createUserResult = try makeUser(id: anonUid)

        let user = try await manager.obtainUser()

        XCTAssertEqual(user.id, anonUid)
        XCTAssertEqual(service.createUserCallsCount, 2)
    }

    func testConcurrentObtainUserFailureFailsAllWaitersWithOneRequest() async throws {
        service.error = MockError.stubbed
        let gate = AsyncGate()
        service.onCreateUser = { await gate.wait() }

        async let first: Qonversion.User? = try? manager.obtainUser()
        async let second: Qonversion.User? = try? manager.obtainUser()
        async let third: Qonversion.User? = try? manager.obtainUser()

        await waitUntil { self.service.createUserCallsCount >= 1 }
        await gate.open()

        let results = await [first, second, third]

        XCTAssertEqual(results.compactMap { $0 }.count, 0)
        XCTAssertEqual(service.createUserCallsCount, 1)
    }

    // MARK: - Migration from the previous SDK generation

    /// The whole upgrade path over a REAL UserService: the install adopts the
    /// legacy uid, the backend answers the create with `already_exists` (422),
    /// and the gate still completes with that existing user.
    func testObtainUserRecoversFromTheCreateConflictOfAMigratedInstall() async throws {
        let legacyUid = "QON_legacy_uid"
        let legacySuiteName = "qonversion.localstorage.main"
        let legacyDefaults = UserDefaults(suiteName: legacySuiteName)
        legacyDefaults?.removePersistentDomain(forName: legacySuiteName)
        defer { legacyDefaults?.removePersistentDomain(forName: legacySuiteName) }

        let migrationStorage = MockLocalStorage()
        migrationStorage.set(string: legacyUid, forKey: "com.qonversion.keys.storedUserID")
        let migrationConfig = InternalConfig(userId: "")
        let processor = MockRequestProcessor()
        let realService = UserService(requestProcessor: processor, localStorage: migrationStorage, internalConfig: migrationConfig)
        let migrationManager = UserManager(
            userService: realService,
            localStorage: migrationStorage,
            internalConfig: migrationConfig,
            userChangesNotifier: notifier,
            logger: LoggerWrapper()
        )

        XCTAssertEqual(migrationConfig.userId, legacyUid, "the legacy uid must be adopted before any request")

        let conflict = QonversionError(
            type: .unknown,
            message: "user already exists",
            error: nil,
            additionalInfo: [ErrorConstants.statusCodeKey.rawValue: 422],
            apiCode: "already_exists",
            apiType: "logical"
        )
        processor.results = [conflict, try makeUser(id: legacyUid)]

        let user = try await migrationManager.obtainUser()

        XCTAssertEqual(user.id, legacyUid)
        XCTAssertEqual(
            processor.processedRequests,
            [Request.createUser(body: ["id": legacyUid]), Request.getUser(id: legacyUid)]
        )
        XCTAssertEqual(migrationConfig.userId, legacyUid)

        // The recovered user is cached: a second demand costs no request.
        let cached = try await migrationManager.obtainUser()

        XCTAssertEqual(cached.id, legacyUid)
        XCTAssertEqual(processor.processedRequests.count, 2)
    }

    // MARK: - Identity

    func testIdentifyAfterCreationLinksIdentity() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()

        let user = try await manager.identify("external_1")

        XCTAssertEqual(user.id, anonUid)
        XCTAssertEqual(service.identityCalls, ["external_1"])
        XCTAssertEqual(service.createIdentityCalls.count, 1)
        XCTAssertEqual(service.createIdentityCalls.first?.externalId, "external_1")
        XCTAssertEqual(service.createIdentityCalls.first?.userId, anonUid)
    }

    func testIdentifySwitchesToExistingLinkedUser() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()

        // The external id is already linked to another Qonversion user.
        service.identityLinkedUid = "QON_other_uid"
        service.userResult = try makeUser(id: "QON_other_uid")

        let user = try await manager.identify("external_1")

        XCTAssertEqual(user.id, "QON_other_uid")
        XCTAssertEqual(config.getUserId(), "QON_other_uid")
        // No createIdentity: the link already exists.
        XCTAssertEqual(service.createIdentityCalls.count, 0)
    }

    func testIdentifyBeforeCreationRunsAfterCreateAndBeforeWaiters() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        let identityGate = AsyncGate()
        service.onCreateIdentity = { await identityGate.wait() }

        // identify arrives first and registers a pending identity.
        async let identified = manager.identify("external_1")
        await waitUntil { self.service.createUserCallsCount >= 1 }

        // A data-sender arrives while identity is still in flight.
        let waiterResumed = Flag()
        let waiter = Task {
            _ = try await manager.obtainUser()
            await waiterResumed.set()
        }

        // Identity is held open → the waiter must NOT resume yet.
        await waitUntil { self.service.createIdentityCalls.count >= 1 }
        try await Task.sleep(nanoseconds: 100_000_000)
        let resumedWhileIdentityInFlight = await waiterResumed.isSet
        XCTAssertFalse(resumedWhileIdentityInFlight, "obtainUser waiter must wait for the pending identity")

        await identityGate.open()
        _ = try await identified
        _ = try? await waiter.value

        await waitUntil { true }
        let resumedAfter = await waiterResumed.isSet
        XCTAssertTrue(resumedAfter)

        // Order: user created first, then identity, and only then waiters were released.
        XCTAssertEqual(service.callLog.first, "createUser")
        XCTAssertTrue(service.callLog.contains("createIdentity"))
        XCTAssertEqual(service.createUserCallsCount, 1)
    }

    func testPendingIdentityFailureFailsIdentifyButReleasesWaitersWithUser() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        service.createIdentityError = MockError.stubbed

        async let identified: Qonversion.User? = try? manager.identify("external_1")
        // The data-sender still gets the created user even though identity failed.
        let user = try await manager.obtainUser()

        let identifyResult = await identified

        XCTAssertNil(identifyResult, "identify must rethrow the identity error")
        XCTAssertEqual(user.id, anonUid)
    }

    // MARK: - Logout

    func testLogoutReturnsToTheOriginalAnonymousUser() async throws {
        // Production semantics: the original anonymous user owns the
        // pre-identify purchases — logout must come back to it, not mint
        // a fresh uid that orphans them.
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        service.identityLinkedUid = "QON_other_uid"
        service.userResult = try makeUser(id: "QON_other_uid")
        _ = try await manager.identify("external_1")
        XCTAssertEqual(config.userId, "QON_other_uid")

        await manager.logout()

        XCTAssertEqual(config.userId, anonUid, "logout returns to the install's original anonymous uid")

        // Next demand recreates/upserts the original backend user.
        service.createUserResult = try makeUser(id: anonUid)
        let user = try await manager.obtainUser()
        XCTAssertEqual(user.id, anonUid)
    }

    func testLogoutOnTheOriginalAnonymousUserIsANoOp() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()

        await manager.logout()

        XCTAssertEqual(config.userId, anonUid)
        XCTAssertEqual(observer.userDidChangeCallsCount, 0, "nothing changed — caches must survive")
    }

    func testIdentifyAfterLogoutRunsTheFullFlowAgain() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        service.identityLinkedUid = "QON_other_uid"
        service.userResult = try makeUser(id: "QON_other_uid")
        _ = try await manager.identify("external_1")
        let identityCallsAfterFirst: Int = service.identityCalls.count

        await manager.logout()
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.identify("external_1")

        XCTAssertGreaterThan(service.identityCalls.count, identityCallsAfterFirst,
                             "logout cleared the link — the next identify must hit the backend, not the local short-circuit")
    }

    func testLogoutDuringTheVeryFirstIdentifyPreventsLateIdentification() async throws {
        // The uid has not moved yet (first identify in flight) — logout must
        // still cancel it; the stale continuation must not identify the user
        // after logout returned.
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        let gate = AsyncGate()
        service.onIdentity = { await gate.wait() }
        service.identityLinkedUid = "QON_other_uid"
        service.userResult = try makeUser(id: "QON_other_uid")

        async let raced = manager.identify("external_1")
        await waitUntil { self.service.identityCalls.count >= 1 }
        await manager.logout()
        await gate.open()

        let result = try? await raced
        XCTAssertNil(result, "the identify the host logged out from must not settle successfully")
        XCTAssertEqual(config.userId, anonUid)
        XCTAssertNil(storage.string(forKey: "qonversion.keys.identityExternalId"))
    }

    func testLogoutCancelsAnInFlightIdentify() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        service.identityLinkedUid = "QON_other_uid"
        service.userResult = try makeUser(id: "QON_other_uid")
        _ = try await manager.identify("external_1")

        // A second identify hangs on the identity request; logout lands mid-flight.
        let gate = AsyncGate()
        service.onIdentity = { await gate.wait() }
        service.identityLinkedUid = "QON_third_uid"
        async let racedIdentify = manager.identify("external_2")
        await waitUntil { self.service.identityCalls.count >= 2 }

        await manager.logout()
        await gate.open()

        let raced = try? await racedIdentify
        XCTAssertNil(raced, "the identify the host logged out from must not settle successfully")
        XCTAssertEqual(config.userId, anonUid, "the logged-out state must not be re-identified by the stale continuation")
    }

    // MARK: - identity coherence

    func testAFailingUserFetchAfterTheSwitchStillPersistsTheIdentity() async throws {
        // The uid moved and was persisted; leaving the identity behind would
        // make the next launch believe the new uid is anonymous.
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        service.identityLinkedUid = "QON_other_uid"
        service.error = MockError.stubbed                                       // the user fetch fails

        do {
            _ = try await manager.identify("external_1")
            XCTFail("Expected the failing user fetch to surface")
        } catch { }

        XCTAssertEqual(storage.string(forKey: UserServiceStorageKeys.userIdKey.rawValue), "QON_other_uid")
        XCTAssertEqual(storage.string(forKey: "qonversion.keys.identityExternalId"), "external_1",
                       "the uid and the identity that caused the switch must be persisted together")
    }

    func testAUidSwitchWithoutAnIdentityClearsTheStoredIdentity() async throws {
        // The switch was not caused by an external id, so the user it lands on
        // is not linked to the one the previous user carried.
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        _ = try await manager.identify("external_1")
        service.userResult = try makeUser(id: ownerUid)

        try await manager.switchToUser(with: ownerUid)

        XCTAssertNil(storage.string(forKey: identityStorageKey),
                     "the previous user's identity must not survive a switch that did not carry one")
    }

    func testARestoreOwnerSwitchLetsTheNextIdentifyWithTheSameIdRelink() async throws {
        // Restore hands the SDK the transactions' owner: the uid moves without
        // an external id. A stale identity left behind would make the host's
        // next identify with that very id a silent no-op on the new user.
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        _ = try await manager.identify("external_1")
        service.userResult = try makeUser(id: ownerUid)
        try await manager.switchToUser(with: ownerUid)

        _ = try await manager.identify("external_1")

        XCTAssertEqual(service.identityCalls.count, 2, "the identify must reach the backend, not answer from the previous user's identity")
        XCTAssertEqual(service.createIdentityCalls.last?.userId, ownerUid, "the external id must be linked to the user the switch landed on")
        XCTAssertEqual(storage.string(forKey: identityStorageKey), "external_1")
    }

    func testUserInfoRacingLogoutDoesNotAnswerWithThePreviousIdentitysUser() async throws {
        // The fetch was built for the identified uid; a logout landing while it
        // is in flight makes its answer belong to a session that is over — and
        // persisting it would file that user under the restored uid's storage.
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        service.identityLinkedUid = identifiedUid
        service.userResult = try makeUser(id: identifiedUid)
        _ = try await manager.identify("external_1")
        let gate = AsyncGate()
        service.onUser = { await gate.wait() }

        async let raced: Qonversion.User = manager.userInfo()
        await waitUntil { self.service.userCallsCount >= 2 }
        await manager.logout()
        await gate.open()

        do {
            _ = try await raced
            XCTFail("Expected the abandoned fetch to fail")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .cancelled)
        } catch {
            XCTFail("A raw \(type(of: error)) must never reach the host")
        }

        XCTAssertEqual(config.userId, anonUid)
        let persisted: Qonversion.User? = try? storage.object(forKey: userStorageKey, dataType: Qonversion.User.self)
        XCTAssertNil(persisted, "the previous identity's user must not be persisted under the new uid")
    }

    func testAnIdentityResumingAfterLogoutIsNotWrittenForTheRestoredUser() async throws {
        // logout bumps the generation BEFORE the uid reverts, so an identify
        // starting inside that window captures the already-bumped generation:
        // the generation alone no longer proves the identity still applies.
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        service.identityLinkedUid = identifiedUid
        service.userResult = try makeUser(id: identifiedUid)
        _ = try await manager.identify("external_1")

        let willChangeGate = AsyncGate()
        let willChangeObserver = SuspendingUserChangeObserver(gate: willChangeGate)
        notifier.add(observer: willChangeObserver)
        let identityGate = AsyncGate()

        async let loggedOut: Void = manager.logout()
        await waitUntil { willChangeObserver.didStart }
        service.onIdentity = { await identityGate.wait() }

        async let raced: Qonversion.User = manager.identify("external_2")
        await waitUntil { self.service.identityCalls.count >= 2 }
        await willChangeGate.open()
        await loggedOut
        await waitUntil { self.config.userId == self.anonUid }
        await identityGate.open()

        do {
            _ = try await raced
            XCTFail("Expected the abandoned identify to fail")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .cancelled)
        } catch {
            XCTFail("A raw \(type(of: error)) must never reach the host")
        }

        XCTAssertNil(storage.string(forKey: identityStorageKey),
                     "the logged out session's identity must not land on the restored user")
    }

    func testIdentifyFailurePropagatesToTheCaller() async throws {
        // The public path must always tell the caller the outcome — no branch
        // may answer with a user while the linking failed.
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        service.createIdentityError = MockError.stubbed

        do {
            _ = try await manager.identify("external_1")
            XCTFail("Expected identify to throw")
        } catch {
            XCTAssertEqual(error as? MockError, .stubbed)
        }
    }

    func testLogoutDuringTheUserFetchOfASwitchDoesNotCacheTheUser() async throws {
        // The switch is in flight when the host logs out: caching its user
        // would resurrect the session that was just ended.
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        service.identityLinkedUid = "QON_other_uid"
        service.userResult = try makeUser(id: "QON_other_uid")
        let gate = AsyncGate()
        service.onIdentity = { await gate.wait() }

        async let raced: Qonversion.User = manager.identify("external_1")
        await waitUntil { self.service.identityCalls.count >= 1 }
        await manager.logout()
        await gate.open()
        _ = try? await raced

        XCTAssertEqual(config.userId, anonUid)
    }

    // MARK: - user stability gate

    func testAwaitUserStabilityRethrowsTheIdentifyFailure() async throws {
        // Production fails the queued remote config completions with the
        // identify error instead of answering for the previous user.
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        let gate = AsyncGate()
        service.onIdentity = { await gate.wait() }
        service.identityError = MockError.stubbed

        async let failing: Qonversion.User = manager.identify("external_1")
        await waitUntil { self.service.identityCalls.count >= 1 }
        async let stability: Void = manager.awaitUserStability()
        await gate.open()
        _ = try? await failing

        do {
            try await stability
            XCTFail("Expected the identify failure to reach the stability gate")
        } catch {
            XCTAssertEqual(error as? MockError, .stubbed)
        }
    }

    func testACancelledIdentifyLeavesTheStabilityGateSilent() async throws {
        // A task cancelled while suspended in URLSession reports
        // URLError(.cancelled), wrapped by the failing layer. That is a
        // teardown, not an identify failure the remote config caller must see.
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        let gate = AsyncGate()
        service.onIdentity = { await gate.wait() }
        service.identityError = QonversionError(type: .identityLoadingFailed, message: nil, error: URLError(.cancelled))

        async let raced: Qonversion.User = manager.identify("external_1")
        await waitUntil { self.service.identityCalls.count >= 1 }
        async let stability: Void = manager.awaitUserStability()
        await gate.open()
        _ = try? await raced

        do {
            try await stability
        } catch {
            XCTFail("A cancelled identify is a teardown, not a failure: \(error)")
        }
    }

    // MARK: - identify single-flight

    func testConcurrentIdentifyWithSameIdSharesOneRequest() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()

        let gate = AsyncGate()
        service.onCreateIdentity = { await gate.wait() }

        async let first = manager.identify("external_1")
        async let second = manager.identify("external_1")

        await waitUntil { self.service.createIdentityCalls.count >= 1 }
        await gate.open()

        _ = try await [first, second]

        XCTAssertEqual(service.createIdentityCalls.count, 1, "the same external id must join the in-flight identify")
    }

    func testConcurrentIdentifyWithDifferentIdsRunSequentially() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()

        let gate = AsyncGate()
        service.onCreateIdentity = { await gate.wait() }

        async let first = manager.identify("external_1")
        await waitUntil { self.service.createIdentityCalls.count >= 1 }
        async let second = manager.identify("external_2")

        // The second identify must wait for the first one to settle.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(service.createIdentityCalls.count, 1)

        await gate.open()
        _ = try await [first, second]

        XCTAssertEqual(service.createIdentityCalls.map(\.externalId), ["external_1", "external_2"])
    }

    // MARK: - User change notifications

    func testLogoutNotifiesUserChangeObservers() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        service.identityLinkedUid = "QON_other_uid"
        service.userResult = try makeUser(id: "QON_other_uid")
        _ = try await manager.identify("external_1")
        let notificationsAfterSwitch: Int = observer.userDidChangeCallsCount

        await manager.logout()

        XCTAssertEqual(observer.userDidChangeCallsCount, notificationsAfterSwitch + 1)
    }

    func testRepeatedIdentifyWithTheSameIdAnswersLocally() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        _ = try await manager.identify("external_1")
        let identityCallsAfterFirst: Int = service.identityCalls.count
        let createIdentityCallsAfterFirst: Int = service.createIdentityCalls.count

        let user = try await manager.identify("external_1")

        XCTAssertEqual(user.id, config.userId)
        XCTAssertEqual(service.identityCalls.count, identityCallsAfterFirst, "an identify on every launch must not cost extra requests")
        XCTAssertEqual(service.createIdentityCalls.count, createIdentityCallsAfterFirst)
    }

    func testIdentifySwitchToLinkedUserNotifiesUserChangeObservers() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()

        service.identityLinkedUid = "QON_other_uid"
        service.userResult = try makeUser(id: "QON_other_uid")

        _ = try await manager.identify("external_1")

        XCTAssertEqual(observer.userDidChangeCallsCount, 1)
    }

    func testIdentitySwitchNotifiesEvenWhenNewUserFetchFails() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()

        // The uid switches, but fetching the new user fails: the old user's
        // caches must still be invalidated — they belong to the previous uid.
        service.identityLinkedUid = "QON_other_uid"
        service.userResult = nil

        _ = try? await manager.identify("external_1")

        XCTAssertEqual(config.getUserId(), "QON_other_uid")
        XCTAssertEqual(observer.userDidChangeCallsCount, 1)
    }

    func testIdentifyKeepingSameUserDoesNotNotifyUserChangeObservers() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()

        _ = try await manager.identify("external_1")

        XCTAssertEqual(observer.userDidChangeCallsCount, 0)
    }

    // MARK: - User info

    func testUserInfoFetchesUserAfterGate() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        service.userResult = try makeUser(id: anonUid)

        let user = try await manager.userInfo()

        XCTAssertEqual(user.id, anonUid)
        XCTAssertEqual(service.createUserCallsCount, 1, "userInfo must pass the creation gate first")
        XCTAssertEqual(service.userCallsCount, 1)
    }

    func testUserInfoAnswersFromTheCacheWhenTheFetchFails() async throws {
        // The ObjC SDK always had an answer here — the user record is
        // persisted locally. Throwing on a network hiccup makes a call that
        // needs no network at all fail.
        service.createUserResult = try makeUser(id: anonUid)
        service.userResult = try makeUser(id: anonUid)
        _ = try await manager.userInfo()
        service.userError = QonversionError(type: .internal)

        let user = try await manager.userInfo()

        XCTAssertEqual(user.id, anonUid, "the persisted user answers offline")
    }

    // MARK: - originalAppVersion

    func testUserInfoStampsTheOriginalAppVersionFromTheStore() async throws {
        // The backend never serves this field — the SDK resolves it on the
        // device and stamps it onto the user it hands back.
        appTransactionReader.originalAppVersionResult = "1.0.3"
        service.createUserResult = try makeUser(id: anonUid)
        service.userResult = try makeUser(id: anonUid)

        let user = try await manager.userInfo()

        XCTAssertEqual(user.originalAppVersion, "1.0.3")
    }

    func testUserInfoLeavesTheOriginalAppVersionNilWhenTheStoreCannotAnswer() async throws {
        appTransactionReader.originalAppVersionResult = nil
        service.createUserResult = try makeUser(id: anonUid)
        service.userResult = try makeUser(id: anonUid)

        let user = try await manager.userInfo()

        XCTAssertNil(user.originalAppVersion)
    }

    func testUserInfoStampsThePersistedUserWhenTheFetchFails() async throws {
        appTransactionReader.originalAppVersionResult = "1.0.3"
        service.createUserResult = try makeUser(id: anonUid)
        service.userResult = try makeUser(id: anonUid)
        _ = try await manager.userInfo()
        service.userError = QonversionError(type: .internal)

        let user = try await manager.userInfo()

        XCTAssertEqual(user.originalAppVersion, "1.0.3", "the cached user carries the version too")
    }

    func testTheStampedOriginalAppVersionIsPersisted() async throws {
        appTransactionReader.originalAppVersionResult = "1.0.3"
        service.createUserResult = try makeUser(id: anonUid)
        service.userResult = try makeUser(id: anonUid)

        _ = try await manager.userInfo()

        let persisted = try XCTUnwrap(try storage.object(forKey: "qonversion.keys.user", dataType: Qonversion.User.self))
        XCTAssertEqual(persisted.originalAppVersion, "1.0.3")
    }

    // MARK: - cancellation never escapes unclassified

    func testObtainUserCancelledByLogoutThrowsAQonversionError() async throws {
        // The pipeline's generation guards throw CancellationError, a Swift
        // runtime type: no `catch let error as QonversionError` can classify
        // it, so it must never leave a public entry point.
        let gate = AsyncGate()
        service.onCreateUser = { await gate.wait() }
        service.createUserResult = try makeUser(id: anonUid)

        async let raced: Qonversion.User = manager.obtainUser()
        await waitUntil { self.service.createUserCallsCount >= 1 }
        await manager.logout()
        await gate.open()

        do {
            _ = try await raced
            XCTFail("Expected the abandoned pipeline to fail")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .cancelled)
        } catch {
            XCTFail("A raw \(type(of: error)) must never reach the host")
        }
    }

    func testUserInfoCancelledByLogoutThrowsAQonversionError() async throws {
        let gate = AsyncGate()
        service.onCreateUser = { await gate.wait() }
        service.createUserResult = try makeUser(id: anonUid)
        service.userResult = try makeUser(id: anonUid)

        async let raced: Qonversion.User = manager.userInfo()
        await waitUntil { self.service.createUserCallsCount >= 1 }
        await manager.logout()
        await gate.open()

        do {
            _ = try await raced
            XCTFail("Expected the abandoned call to fail")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .cancelled)
        } catch {
            XCTFail("A raw \(type(of: error)) must never reach the host")
        }
    }

    func testIdentifyCancelledByLogoutThrowsAQonversionError() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        let gate = AsyncGate()
        service.onIdentity = { await gate.wait() }
        service.identityLinkedUid = "QON_other_uid"
        service.userResult = try makeUser(id: "QON_other_uid")

        async let raced: Qonversion.User = manager.identify("external_1")
        await waitUntil { self.service.identityCalls.count >= 1 }
        await manager.logout()
        await gate.open()

        do {
            _ = try await raced
            XCTFail("Expected the abandoned identify to fail")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .cancelled)
        } catch {
            XCTFail("A raw \(type(of: error)) must never reach the host")
        }
    }

    func testACancelledUserFetchIsNotAnsweredFromTheStaleCache() async throws {
        // The offline answer exists for outages. A cancelled fetch is a user
        // switch, and the persisted record belongs to the PREVIOUS user.
        service.createUserResult = try makeUser(id: anonUid)
        service.userResult = try makeUser(id: anonUid)
        _ = try await manager.userInfo()
        service.userError = CancellationError()

        do {
            _ = try await manager.userInfo()
            XCTFail("Expected the cancelled fetch to fail")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .cancelled)
        } catch {
            XCTFail("A raw \(type(of: error)) must never reach the host")
        }
    }

    func testUserInfoThrowsWhenThereIsNoUserAtAll() async throws {
        // "Nothing local" and "the gate failed" are the same situation: the
        // gate is what puts a user on the device, so once it has passed there
        // is always something to answer with. A gate failure must still
        // surface — the caller has no user.
        service.error = QonversionError(type: .internal)

        do {
            _ = try await manager.userInfo()
            XCTFail("Expected the failure to surface")
        } catch let error as QonversionError {
            XCTAssertEqual(error.type, .internal)
        }
    }
}

// MARK: - Async helpers

/// A reusable async gate: `wait()` suspends until `open()` is called.
private actor AsyncGateStorage {
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

private final class AsyncGate: @unchecked Sendable {
    private let storage = AsyncGateStorage()
    func open() async { await storage.open() }
    func wait() async { await storage.wait() }
}

private actor Flag {
    private(set) var isSet = false
    func set() { isSet = true }
}

/// Holds the will-change step open, so a test can park logout inside the window
/// it opens between the generation bump and the uid revert.
private final class SuspendingUserChangeObserver: UserChangedObserver, @unchecked Sendable {

    private let gate: AsyncGate
    private let lock = NSLock()
    private var started = false

    var didStart: Bool {
        lock.lock()
        defer { lock.unlock() }

        return started
    }

    init(gate: AsyncGate) {
        self.gate = gate
    }

    func userWillChange() async {
        lock.lock()
        started = true
        lock.unlock()

        await gate.wait()
    }

    func userDidChange() {}
}
