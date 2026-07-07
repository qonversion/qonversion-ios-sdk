//
//  AsyncMulticast.swift
//  Qonversion
//

import Foundation

/// Fans one sequence of values out to any number of independent AsyncStreams
/// (StoreKit's Transaction.updates style: every stream() call is a separate
/// subscription). Values yielded while nobody subscribes are dropped.
final class AsyncMulticast<Element> {

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    func yield(_ element: Element) {
        lock.lock()
        let active = Array(continuations.values)
        lock.unlock()

        active.forEach { $0.yield(element) }
    }
}
