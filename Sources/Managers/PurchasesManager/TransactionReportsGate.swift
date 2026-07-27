//
//  TransactionReportsGate.swift
//  Qonversion
//

import Foundation

/// Serializes transaction reporting between the launch sweep of unfinished
/// transactions and the Transaction.updates listener: whoever takes the id
/// first reports it, the other path skips. A failed report releases the id so
/// the next attempt can retry.
actor TransactionReportsGate {

    private var takenIds: Set<String> = []

    func tryTake(_ id: String) -> Bool {
        guard !takenIds.contains(id) else { return false }
        takenIds.insert(id)
        return true
    }

    func release(_ id: String) {
        takenIds.remove(id)
    }

    /// The new user's restore must re-report everything: the gate belongs to
    /// the reporting session of one user.
    func reset() {
        takenIds.removeAll()
    }
}
