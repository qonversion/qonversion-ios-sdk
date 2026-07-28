//
//  AsyncMulticast.swift
//  Qonversion
//

import Foundation

/// Fans one sequence of values out to any number of independent AsyncStreams
/// (StoreKit's Transaction.updates style: every stream() call is a separate
/// subscription).
///
/// Backlog policy (`replaysBacklog: true`)
/// --------------------------------------
/// Every yielded value is kept in a bounded backlog and replayed to EVERY
/// subscriber that arrives afterwards, independently of whether somebody was
/// already listening when the value was produced. A subscriber reads the
/// backlog exactly once — at subscription time, when by definition nothing has
/// been delivered to it yet — and receives live values from then on, so no
/// value is ever delivered to the same subscriber twice.
///
/// This matters because subscriptions are not simultaneous: the projection
/// built by `entitlementsUpdates()` attaches while the AsyncStream is being
/// constructed, so a host that subscribes to it first (exactly what the Sample
/// and the README show) would otherwise consume the launch backlog and starve
/// the `deferredPurchases()` subscription it creates a moment later.
///
/// The backlog is bounded two ways, so it stays a launch-window replay and
/// never becomes an unbounded event log:
///   * by count — at most `maxPending` values, oldest dropped first;
///   * by age — a value older than `backlogLifetime` is never replayed.
///
/// With `replaysBacklog: false` (the default) values yielded to nobody are
/// simply dropped.
// @unchecked: the continuations and the backlog are lock-guarded.
final class AsyncMulticast<Element: Sendable>: @unchecked Sendable {

    /// Bounds the replay backlog; the oldest values are dropped first.
    static var maxPending: Int { 10 }

    /// Bounds each subscriber's own buffer. INVARIANT: strictly greater than
    /// ``maxPending`` — the whole backlog is replayed before a subscriber
    /// drains, so the headroom absorbs live values instead of evicting it.
    static var subscriberBufferSize: Int { maxPending * 4 }

    /// How long a value stays replayable to subscribers arriving after it.
    /// Sized for "the host finished wiring its streams up", not for the whole
    /// session.
    static var defaultBacklogLifetime: TimeInterval { 300 }

    private struct BacklogEntry {
        let element: Element
        let addedAt: Date
    }

    private let replaysBacklog: Bool
    private let backlogLifetime: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var backlog: [BacklogEntry] = []

    init(
        replaysBacklog: Bool = false,
        backlogLifetime: TimeInterval = AsyncMulticast.defaultBacklogLifetime,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.replaysBacklog = replaysBacklog
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

    func yield(_ element: Element) {
        lock.lock()
        if replaysBacklog {
            pruneBacklogLocked()
            let entry = BacklogEntry(element: element, addedAt: now())
            backlog.append(entry)
            if backlog.count > Self.maxPending {
                backlog.removeFirst(backlog.count - Self.maxPending)
            }
        }
        let active: [AsyncStream<Element>.Continuation] = Array(continuations.values)
        lock.unlock()

        active.forEach { $0.yield(element) }
    }

    // MARK: - Private

    /// Registers the subscriber and replays everything it has missed, all
    /// under one lock. The replay yields INSIDE the critical section on
    /// purpose: `Continuation.yield` never blocks under `.bufferingNewest`,
    /// and doing it outside would let a value yielded concurrently reach this
    /// subscriber BEFORE the backlog it is supposed to follow — the host would
    /// see the launch purchase after the live one.
    private func register(id: UUID, continuation: AsyncStream<Element>.Continuation) {
        lock.lock()
        defer { lock.unlock() }

        continuations[id] = continuation
        guard replaysBacklog else { return }

        pruneBacklogLocked()
        backlog.forEach { continuation.yield($0.element) }
    }

    private func unregister(id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }

    private func pruneBacklogLocked() {
        guard backlogLifetime.isFinite else { return }

        let deadline: Date = now().addingTimeInterval(-backlogLifetime)
        backlog.removeAll { $0.addedAt < deadline }
    }
}
