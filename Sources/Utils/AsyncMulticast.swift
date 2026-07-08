//
//  AsyncMulticast.swift
//  Qonversion
//

import Foundation

/// Fans one sequence of values out to any number of independent AsyncStreams
/// (StoreKit's Transaction.updates style: every stream() call is a separate
/// subscription). By default values yielded while nobody subscribes are
/// dropped; with `buffersWhenNoSubscribers` they are kept and delivered to
/// the first subscriber (e.g. promo intents arriving before the host is ready).
final class AsyncMulticast<Element> {

    /// Bounds the no-subscriber backlog; the oldest values are dropped first.
    static var maxPending: Int { 10 }

    private let buffersWhenNoSubscribers: Bool
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var pending: [Element] = []

    init(buffersWhenNoSubscribers: Bool = false) {
        self.buffersWhenNoSubscribers = buffersWhenNoSubscribers
    }

    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let backlog = pending
            pending = []
            lock.unlock()

            backlog.forEach { continuation.yield($0) }

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
        if active.isEmpty && buffersWhenNoSubscribers {
            pending.append(element)
            if pending.count > Self.maxPending {
                pending.removeFirst(pending.count - Self.maxPending)
            }
        }
        lock.unlock()

        active.forEach { $0.yield(element) }
    }
}
