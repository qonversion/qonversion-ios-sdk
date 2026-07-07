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

    private let anonUid = "QON_anon_uid"

    override func setUp() {
        super.setUp()
        service = MockUserService()
        storage = MockLocalStorage()
        config = InternalConfig(userId: anonUid)
        notifier = UserChangesNotifier()
        observer = UserChangeObserverSpy()
        notifier.add(observer: observer)
        manager = makeManager()
    }

    override func tearDown() {
        manager = nil
        observer = nil
        notifier = nil
        config = nil
        storage = nil
        service = nil
        super.tearDown()
    }

    private func makeManager() -> UserManager {
        UserManager(userService: service, localStorage: storage, internalConfig: config, userChangesNotifier: notifier, logger: LoggerWrapper())
    }

    private func makeUser(id: String, environment: String = "sandbox") throws -> Qonversion.User {
        let json = #"{"id": "\#(id)", "created": 1700000000, "environment": "\#(environment)"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
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

    func testLogoutResetsToFreshAnonymousUser() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()
        _ = try await manager.identify("external_1")

        service.generatedUserId = "QON_fresh_uid"
        await manager.logout()

        // Next demand creates a NEW backend user for the fresh uid.
        service.createUserResult = try makeUser(id: "QON_fresh_uid")
        let user = try await manager.obtainUser()

        XCTAssertEqual(user.id, "QON_fresh_uid")
        XCTAssertEqual(service.createUserCallsCount, 2)
    }

    // MARK: - User change notifications

    func testLogoutNotifiesUserChangeObservers() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()

        await manager.logout()

        XCTAssertEqual(observer.userDidChangeCallsCount, 1)
    }

    func testIdentifySwitchToLinkedUserNotifiesUserChangeObservers() async throws {
        service.createUserResult = try makeUser(id: anonUid)
        _ = try await manager.obtainUser()

        service.identityLinkedUid = "QON_other_uid"
        service.userResult = try makeUser(id: "QON_other_uid")

        _ = try await manager.identify("external_1")

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
