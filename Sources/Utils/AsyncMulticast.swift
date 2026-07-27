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
// @unchecked: the continuations and backlog are lock-guarded.
final class AsyncMulticast<Element: Sendable>: @unchecked Sendable {

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
        // Slow consumers keep only the newest values instead of growing the
        // buffer without bound.
        AsyncStream(bufferingPolicy: .bufferingNewest(Self.maxPending)) { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            // The backlog is replayed to EVERY subscriber that arrives before
            // the next live value: first-subscriber-takes-all would let one
            // stream (e.g. a projection) swallow what another one is waiting
            // for. It is dropped by the first live delivery below.
            let backlog: [Element] = pending
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
        } else {
            // Somebody is listening live, so nobody is late anymore: the
            // replay window has done its job.
            pending = []
        }
        lock.unlock()

        active.forEach { $0.yield(element) }
    }
}
