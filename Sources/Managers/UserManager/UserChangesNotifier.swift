//
//  UserChangesNotifier.swift
//  Qonversion
//

import Foundation

/// A cache that must not survive a user switch (logout or identify resolving
/// to another user) registers itself as an observer.
protocol UserChangedObserver: AnyObject {
    func userDidChange()
}

protocol UserChangesNotifierInterface {
    func add(observer: UserChangedObserver)
    func notifyUserChanged()
}

final class UserChangesNotifier: UserChangesNotifierInterface {

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

    func notifyUserChanged() {
        lock.lock()
        let observers = boxes.compactMap { $0.observer }
        lock.unlock()

        observers.forEach { $0.userDidChange() }
    }
}
