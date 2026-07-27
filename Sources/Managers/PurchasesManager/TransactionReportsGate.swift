//
//  TransactionReportsGate.swift
//  Qonversion
//

import Foundation

/// Serializes transaction reporting across every path that can post the same
/// purchase: the launch sweep of unfinished transactions, the
/// Transaction.updates listener, and the offline replay of the requests queue
/// (which at launch runs concurrently with the sweep and may hold a queued
/// report for the very transaction the sweep is about to send). Whoever takes
/// the id first reports it, the other paths skip. A failed report releases the
/// id so the next attempt can retry.
///
/// One instance SDK-wide — see MiscAssembly.transactionReportsGate().
// @unchecked: the id set is lock-guarded; synchronous on purpose — the reset
// on a user change must be ordered before the next restore call.
final class TransactionReportsGate: @unchecked Sendable {

    private let lock = NSLock()
    private var takenIds: Set<String> = []

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
        takenIds.remove(id)
    }

    /// The new user's restore must re-report everything: the gate belongs to
    /// the reporting session of one user.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        takenIds.removeAll()
    }
}
