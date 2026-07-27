//
//  TransactionReportsGate.swift
//  Qonversion
//

import Foundation

/// Serializes transaction reporting between the launch sweep of unfinished
/// transactions and the Transaction.updates listener: whoever takes the id
/// first reports it, the other path skips. A failed report releases the id so
/// the next attempt can retry.
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
