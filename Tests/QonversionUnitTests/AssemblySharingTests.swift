//
//  AssemblySharingTests.swift
//  QonversionUnitTests
//
//  Ownership rules of the assembly graph: state that is shared by design has
//  exactly one instance; per-service components stay per-service (a decision
//  fixated deliberately — see the review registry).
//

import XCTest
@testable import Qonversion

final class AssemblySharingTests: XCTestCase {

    private func makeMiscAssembly() -> (MiscAssembly, ServicesAssembly) {
        let internalConfig = InternalConfig(userId: "user_abc")
        let miscAssembly = MiscAssembly(apiKey: "test-key", userDefaults: TestDefaults.makeIsolated(), internalConfig: internalConfig)
        let servicesAssembly = ServicesAssembly(apiKey: "test-key", miscAssembly: miscAssembly, baseURL: nil)
        miscAssembly.servicesAssembly = servicesAssembly
        return (miscAssembly, servicesAssembly)
    }

    func testRequestsStorageIsOneInstanceSdkWide() {
        let (miscAssembly, _) = makeMiscAssembly()

        let first = miscAssembly.requestsStorage() as AnyObject
        let second = miscAssembly.requestsStorage() as AnyObject

        XCTAssertTrue(first === second, "every per-service processor must share the one replay queue — separate locks over the shared UserDefaults key lose requests")
    }

    func testUserSwitchClearsTheReplayQueue() {
        let (miscAssembly, _) = makeMiscAssembly()
        let storage = miscAssembly.requestsStorage()
        storage.append(StoredRequest(url: "https://api2.qonversion.io/v4/users/OLD_UID/purchases", method: "POST", body: nil, dedupKey: nil))

        miscAssembly.userChangesNotifier().notifyUserChanged()

        XCTAssertTrue(storage.fetchRequests().isEmpty, "queued requests carry the previous user's uid and must not replay after a switch")
    }

    func testRequestProcessorsStayPerService() {
        // Fixates the deliberate design decision: each service owns its
        // processor (and with it its rate limiter and critical latch).
        let (_, servicesAssembly) = makeMiscAssembly()

        let first = servicesAssembly.requestProcessor() as AnyObject
        let second = servicesAssembly.requestProcessor() as AnyObject

        XCTAssertFalse(first === second)
    }

    func testEntitlementsManagerIsOneInstanceSdkWide() {
        let assembly = QonversionAssembly(apiKey: "test-key", userDefaults: TestDefaults.makeIsolated())

        let first = assembly.entitlementsManager() as AnyObject
        let second = assembly.entitlementsManager() as AnyObject

        XCTAssertTrue(first === second, "two instances would double every user-change invalidation")
    }
}
