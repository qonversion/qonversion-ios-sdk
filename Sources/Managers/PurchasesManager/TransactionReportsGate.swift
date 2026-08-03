//
//  TransactionReportsGate.swift
//  Qonversion
//

import Foundation

/// Serializes transaction reporting across every path that can post the same
/// purchase: the launch sweep of unfinished transactions, the
/// Transaction.updates listener, and the offline replay of the requests queue
/// (which at launch runs concurrently with the sweep and may hold a queued
/// report for the very transaction the sweep is about to send).
///
/// The gate guards the POST, not the transaction's outcome. Reporting a
/// purchase is only one third of it: the SDK must also finish the StoreKit
/// transaction and surface one deferred purchase, and the replay does neither
/// — it is an HTTP resend with no StoreKit context. So a taken id is released
/// on every terminal outcome:
///
/// - the report failed — ``release(_:)``, the next attempt may retry it;
/// - the report was delivered — ``markReported(_:)``, which also records the
///   delivery so that a later path finishes and surfaces the transaction
///   through ``wasReported(_:)`` instead of posting it a second time.
///
/// A holder that produces the whole outcome itself (the purchases funnel) never
/// has to release: it keeps the id until ``reset()``.
///
/// ``release(_:)``, ``markReported(_:)`` and ``markDelivered(_:)`` belong to the
/// holder of the id and to the session it was taken in: after ``reset()`` they
/// do nothing, so an outcome that lands past a user switch cannot speak for the
/// new user's session.
///
/// One instance SDK-wide — see MiscAssembly.transactionReportsGate().
// @unchecked: the id sets are lock-guarded; synchronous on purpose — the reset
// on a user change must be ordered before the next restore call.
final class TransactionReportsGate: @unchecked Sendable {

    private let lock = NSLock()
    private var takenIds: Set<String> = []
    private var reportedIds: Set<String> = []

    func tryTake(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !takenIds.contains(id) else { return false }
        takenIds.insert(id)
        return true
    }

    func release(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard takenIds.contains(id) else { return }
        takenIds.remove(id)
    }

    /// The report reached the backend. Hands the id back so a path that can
    /// finish and surface the transaction may take it, while
    /// ``wasReported(_:)`` keeps that path from posting the purchase again.
    func markReported(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard takenIds.contains(id) else { return }
        reportedIds.insert(id)
        takenIds.remove(id)
    }

    /// The report reached the backend, but the id stays taken: for the holder
    /// that produces the whole outcome itself and never hands the transaction
    /// over. Only ``wasReported(_:)`` learns anything from it.
    func markDelivered(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard takenIds.contains(id) else { return }
        reportedIds.insert(id)
    }

    /// True when this transaction's report already reached the backend in this
    /// session — the caller still owes it a finish and a deferred purchase.
    func wasReported(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return reportedIds.contains(id)
    }

    /// The new user's restore must re-report everything: the gate belongs to
    /// the reporting session of one user.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        takenIds.removeAll()
        reportedIds.removeAll()
    }
}
