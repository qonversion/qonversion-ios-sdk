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

    func testTheOverriddenStoreKitWrapperGetsTheFacadeAsItsDelegate() {
        // The integration test seam must behave like production wiring:
        // without the delegate the facade is blind to promo purchase intents.
        let (_, servicesAssembly) = makeMiscAssembly()
        let wrapper = MockStoreKit2Wrapper()
        servicesAssembly.storeKitWrapperOverride = wrapper

        let facade: StoreKitFacade = servicesAssembly.storeKitFacade()

        XCTAssertTrue(wrapper.delegate === facade)
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
        // processor (and with it its rate limiter).
        let (_, servicesAssembly) = makeMiscAssembly()

        let first = servicesAssembly.requestProcessor() as AnyObject
        let second = servicesAssembly.requestProcessor() as AnyObject

        XCTAssertFalse(first === second)
    }

    func testTheCriticalErrorLatchIsOneInstanceAcrossTheQonversionAssembly() {
        // The processors stay per service, but the revoked-key stop switch
        // must not: the first service to be rejected has to stop the rest.
        // Scope is this assembly graph — NoCodes builds its own processor with
        // its own lock and is deliberately not wired to this latch.
        let (miscAssembly, servicesAssembly) = makeMiscAssembly()

        let firstLatch = miscAssembly.criticalErrorLatch()
        let secondLatch = miscAssembly.criticalErrorLatch()
        XCTAssertTrue(firstLatch === secondLatch)

        let firstProcessor = servicesAssembly.requestProcessor() as? RequestProcessor
        let secondProcessor = servicesAssembly.requestProcessor() as? RequestProcessor
        XCTAssertNotNil(firstProcessor)
        XCTAssertTrue(firstProcessor?.criticalErrorLatch === firstLatch)
        XCTAssertTrue(secondProcessor?.criticalErrorLatch === firstLatch)
    }

    func testEntitlementsManagerIsOneInstanceSdkWide() {
        let assembly = QonversionAssembly(apiKey: "test-key", userDefaults: TestDefaults.makeIsolated())

        let first = assembly.entitlementsManager() as AnyObject
        let second = assembly.entitlementsManager() as AnyObject

        XCTAssertTrue(first === second, "two instances would double every user-change invalidation")
    }
}

// MARK: - user-change observer registration

final class UserChangeObserverOrderTests: XCTestCase {

    func testObserversAreRegisteredInADeterministicOrder() {
        // Left to lazy graph construction the order is whatever the first
        // caller happens to build; the teardown of a user switch must not
        // depend on that.
        let assembly = QonversionAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated())

        assembly.registerUserChangeObservers()

        let observers = assembly.servicesAssembly.miscAssembly.userChangesNotifier().registeredObservers
        let types: [String] = observers.map { String(describing: type(of: $0)) }
        XCTAssertEqual(types.first, "ReplayQueueUserObserver", "the previous user's queued requests stop first")
        XCTAssertEqual(types.dropFirst().first, "PurchasesManager", "then the purchase bookkeeping")
        XCTAssertEqual(Set(types.dropFirst(2)),
                       ["EntitlementsManager", "ProductsManager", "RemoteConfigManager", "DeviceManager", "UserPropertiesManager"],
                       "every user-scoped cache is registered")
    }

    func testThePendingUserPropertiesAreTornDownOnAUserSwitch() {
        // Properties queued for the previous user must never be posted under
        // the new uid.
        let assembly = QonversionAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated())

        assembly.registerUserChangeObservers()

        let observers = assembly.servicesAssembly.miscAssembly.userChangesNotifier().registeredObservers
        let types: [String] = observers.map { String(describing: type(of: $0)) }
        XCTAssertTrue(types.contains("UserPropertiesManager"), "the pending properties batch is user-scoped state")
    }

    func testRegisteringTwiceKeepsOneEntryPerObserver() {
        let assembly = QonversionAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated())

        assembly.registerUserChangeObservers()
        assembly.registerUserChangeObservers()

        XCTAssertEqual(assembly.servicesAssembly.miscAssembly.userChangesNotifier().registeredObservers.count, 7)
    }

    func testTheTeardownOrderDoesNotDependOnTheConstructionOrder() {
        // Building the caches first must not push the queue teardown behind
        // them: the order is declared, not emergent.
        let assembly = QonversionAssembly(apiKey: "test", userDefaults: TestDefaults.makeIsolated())
        _ = assembly.remoteConfigManager()
        _ = assembly.entitlementsManager()
        _ = assembly.purchasesManager()
        _ = assembly.deviceManager()
        _ = assembly.servicesAssembly.miscAssembly.requestsStorage()

        let types: [String] = assembly.servicesAssembly.miscAssembly.userChangesNotifier().registeredObservers.map { String(describing: type(of: $0)) }

        XCTAssertEqual(types.first, "ReplayQueueUserObserver")
        XCTAssertEqual(types.dropFirst().first, "PurchasesManager")
    }
}
