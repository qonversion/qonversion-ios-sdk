//
//  AsyncMulticast.swift
//  Qonversion
//

import Foundation

/// What a multicast does with a value produced while nobody is listening.
enum MulticastBacklog: Sendable, Equatable {

    /// The value is dropped.
    case dropped

    /// The value is kept and replayed to EVERY subscriber arriving inside the
    /// backlog lifetime. For idempotent snapshots, where reading the latest
    /// state again costs the host nothing.
    case replayed

    /// The value waits and is handed to the FIRST subscriber that arrives,
    /// which consumes it: nobody after that receives it. For events the host
    /// acts on, where a second delivery would repeat the action.
    case deliveredOnce
}

/// Fans one sequence of values out to any number of independent AsyncStreams
/// (StoreKit's Transaction.updates style: every stream() call is a separate
/// subscription).
///
/// A value produced while subscribers are listening is broadcast to all of
/// them, whatever the backlog policy is — the policy only decides the fate of
/// a value produced with nobody listening, see ``MulticastBacklog``.
///
/// The backlog is bounded two ways, so it never becomes an unbounded event
/// log:
///   * by count — at most `maxPending` values, oldest dropped first;
///   * by age — a value older than `backlogLifetime` is never delivered. An
///     infinite lifetime makes a value wait for its subscriber indefinitely,
///     which is what a value that must not be lost needs.
// @unchecked: the continuations and the backlog are lock-guarded.
final class AsyncMulticast<Element: Sendable>: @unchecked Sendable {

    /// Bounds the backlog; the oldest values are dropped first.
    static var maxPending: Int { 10 }

    /// Bounds each subscriber's own buffer. INVARIANT: strictly greater than
    /// ``maxPending`` — a whole backlog can be handed over before a subscriber
    /// drains, so the headroom absorbs live values instead of evicting it.
    static var subscriberBufferSize: Int { maxPending * 4 }

    /// How long a value stays deliverable to subscribers arriving after it.
    /// Sized for "the host finished wiring its streams up", not for the whole
    /// session.
    static var defaultBacklogLifetime: TimeInterval { 300 }

    private struct BacklogEntry {
        let element: Element
        let addedAt: Date
        // Cleared once it has run: a replayed value must not report a second
        // delivery.
        var onDelivery: (@Sendable () -> Void)?
    }

    let backlog: MulticastBacklog
    let backlogLifetime: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var backlogEntries: [BacklogEntry] = []

    init(
        backlog: MulticastBacklog = .dropped,
        backlogLifetime: TimeInterval = AsyncMulticast.defaultBacklogLifetime,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.backlog = backlog
        self.backlogLifetime = backlogLifetime
        self.now = now
    }

    /// TEST SEAM. Racy by construction, so production code must not branch on
    /// it; it exists only so tests can observe unregistration.
    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    func stream() -> AsyncStream<Element> {
        // Slow consumers keep only the newest values instead of growing the
        // buffer without bound.
        return AsyncStream(bufferingPolicy: .bufferingNewest(Self.subscriberBufferSize)) { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            let id = UUID()
            self.register(id: id, continuation: continuation)

            continuation.onTermination = { [weak self] _ in
                self?.unregister(id: id)
            }
        }
    }

    /// Broadcasts to every subscriber listening right now; with none, the
    /// backlog policy decides what happens to the value. `onDelivery` runs
    /// once, when the value first reaches a subscriber — never for a value
    /// that expires or is evicted before that.
    func yield(_ element: Element, onDelivery: (@Sendable () -> Void)? = nil) {
        lock.lock()
        pruneBacklogLocked()
        let active: [AsyncStream<Element>.Continuation] = Array(continuations.values)
        let isDelivered: Bool = !active.isEmpty
        let addedAt: Date = now()

        switch backlog {
        case .dropped:
            break
        case .replayed:
            let hook: (@Sendable () -> Void)? = isDelivered ? nil : onDelivery
            let entry = BacklogEntry(element: element, addedAt: addedAt, onDelivery: hook)
            appendBacklogLocked(entry)
        case .deliveredOnce:
            if !isDelivered {
                let entry = BacklogEntry(element: element, addedAt: addedAt, onDelivery: onDelivery)
                appendBacklogLocked(entry)
            }
        }
        lock.unlock()

        active.forEach { $0.yield(element) }
        if isDelivered {
            onDelivery?()
        }
    }

    /// Drops the values kept for future subscribers. A snapshot of a user the
    /// SDK has left must not be replayed to the next one.
    func clearBacklog() {
        lock.lock()
        defer { lock.unlock() }
        backlogEntries.removeAll()
    }

    // MARK: - Private

    /// Registers the subscriber and hands it the backlog, all under one lock.
    /// The yields happen INSIDE the critical section on purpose:
    /// `Continuation.yield` never blocks under `.bufferingNewest`, and doing
    /// it outside would let a value yielded concurrently reach this subscriber
    /// BEFORE the backlog it is supposed to follow — the host would see the
    /// launch purchase after the live one.
    private func register(id: UUID, continuation: AsyncStream<Element>.Continuation) {
        lock.lock()
        continuations[id] = continuation
        pruneBacklogLocked()

        var hooks: [@Sendable () -> Void] = []
        switch backlog {
        case .dropped:
            break
        case .replayed:
            for index in backlogEntries.indices {
                continuation.yield(backlogEntries[index].element)
                if let hook = backlogEntries[index].onDelivery {
                    hooks.append(hook)
                    backlogEntries[index].onDelivery = nil
                }
            }
        case .deliveredOnce:
            let handedOver: [BacklogEntry] = backlogEntries
            backlogEntries.removeAll()
            handedOver.forEach { entry in
                continuation.yield(entry.element)
                if let hook = entry.onDelivery {
                    hooks.append(hook)
                }
            }
        }
        lock.unlock()

        // Outside the lock: a delivery hook is caller code and may take locks
        // or touch storage of its own.
        hooks.forEach { $0() }
    }

    private func unregister(id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }

    private func appendBacklogLocked(_ entry: BacklogEntry) {
        backlogEntries.append(entry)
        if backlogEntries.count > Self.maxPending {
            backlogEntries.removeFirst(backlogEntries.count - Self.maxPending)
        }
    }

    private func pruneBacklogLocked() {
        guard backlogLifetime.isFinite else { return }

        let deadline: Date = now().addingTimeInterval(-backlogLifetime)
        backlogEntries.removeAll { $0.addedAt < deadline }
    }
}
