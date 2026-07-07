//
//  UserChangesNotifierTests.swift
//  QonversionUnitTests
//
//  User-scoped caches must not survive a user switch (logout / identify that
//  resolves to another user). The notifier fans the switch out to registered
//  caches (TDD — written before the implementation).
//

import XCTest
@testable import Qonversion

private final class ObserverSpy: UserChangedObserver {
    private(set) var userDidChangeCallsCount = 0
    func userDidChange() { userDidChangeCallsCount += 1 }
}

final class UserChangesNotifierTests: XCTestCase {

    func testNotifiesAllRegisteredObservers() {
        let notifier = UserChangesNotifier()
        let first = ObserverSpy()
        let second = ObserverSpy()
        notifier.add(observer: first)
        notifier.add(observer: second)

        notifier.notifyUserChanged()

        XCTAssertEqual(first.userDidChangeCallsCount, 1)
        XCTAssertEqual(second.userDidChangeCallsCount, 1)
    }

    func testObserverAddedTwiceIsNotifiedOnce() {
        let notifier = UserChangesNotifier()
        let observer = ObserverSpy()
        notifier.add(observer: observer)
        notifier.add(observer: observer)

        notifier.notifyUserChanged()

        XCTAssertEqual(observer.userDidChangeCallsCount, 1)
    }

    func testObserversAreHeldWeakly() {
        let notifier = UserChangesNotifier()
        var observer: ObserverSpy? = ObserverSpy()
        weak var weakObserver = observer
        notifier.add(observer: observer!)

        observer = nil

        XCTAssertNil(weakObserver, "the notifier must not retain its observers")
        notifier.notifyUserChanged()
    }
}
