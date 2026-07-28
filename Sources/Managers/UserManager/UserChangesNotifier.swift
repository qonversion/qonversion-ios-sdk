//
//  UserChangesNotifier.swift
//  Qonversion
//

import Foundation

/// The teardown order of a user switch, declared instead of emergent: the
/// registration order depends on which manager the graph happens to build
/// first, which is not something the SDK's behavior may rest on.
enum UserChangeTeardownPriority {

    /// Stop sending the previous user's queued requests first.
    static let outgoingQueue = 0

    /// Then the purchase bookkeeping, so a restore right after the switch can
    /// re-report the store transactions.
    static let purchaseBookkeeping = 10

    /// Then everything that is merely cached.
    static let cache = 20
}

/// A cache that must not survive a user switch (logout or identify resolving
/// to another user) registers itself as an observer.
protocol UserChangedObserver: AnyObject {
    /// The last moment at which the previous user's uid is still the current
    /// one: data queued under it has to be claimed here or never.
    ///
    /// The switch waits for this to return, and the host waits for the switch
    /// (identify at launch, logout behind a sign-out button), so an observer
    /// MUST NOT block it — no network, no I/O, no deadline to wait out. The
    /// contract is a synchronous handoff: snapshot whatever belongs to the
    /// outgoing user (its uid included) and take it out of the shared state
    /// before returning, then send it from a background task. A post that owns
    /// its own snapshot can run arbitrarily late and still be attributed
    /// correctly, because there is nothing current left for it to read.
    func userWillChange() async

    func userDidChange()

    /// Lower runs first. See ``UserChangeTeardownPriority``.
    var userChangeTeardownPriority: Int { get }
}

extension UserChangedObserver {

    func userWillChange() async {}

    var userChangeTeardownPriority: Int { UserChangeTeardownPriority.cache }
}

/// Sendable: the will-change step is awaited from the user gate's actor, which
/// sends the notifier across that isolation boundary.
protocol UserChangesNotifierInterface: Sendable {
    func add(observer: UserChangedObserver)
    func notifyUserWillChange() async
    func notifyUserChanged()
}

// @unchecked: the observer list is lock-guarded.
final class UserChangesNotifier: UserChangesNotifierInterface, @unchecked Sendable {

    private struct WeakBox {
        weak var observer: UserChangedObserver?
    }

    private let lock = NSLock()
    private var boxes: [WeakBox] = []

    func add(observer: UserChangedObserver) {
        lock.lock()
        defer { lock.unlock() }

        boxes.removeAll { $0.observer == nil }
        guard !boxes.contains(where: { $0.observer === observer }) else { return }
        boxes.append(WeakBox(observer: observer))
    }

    /// The live observers in teardown order: by declared priority, and by
    /// registration order within one priority (the sort is made stable by the
    /// index tiebreak — Swift's sort is not).
    var registeredObservers: [UserChangedObserver] {
        lock.lock()
        let observers: [UserChangedObserver] = boxes.compactMap { $0.observer }
        lock.unlock()

        return observers
            .enumerated()
            .sorted { ($0.element.userChangeTeardownPriority, $0.offset) < ($1.element.userChangeTeardownPriority, $1.offset) }
            .map { $0.element }
    }

    /// Sequential on purpose: an observer flushing data under the outgoing uid
    /// must finish before the next one runs, in the same declared order the
    /// teardown uses.
    func notifyUserWillChange() async {
        let observers: [UserChangedObserver] = registeredObservers

        for observer in observers {
            await observer.userWillChange()
        }
    }

    func notifyUserChanged() {
        let observers: [UserChangedObserver] = registeredObservers

        observers.forEach { $0.userDidChange() }
    }
}
