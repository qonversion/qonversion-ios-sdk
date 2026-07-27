//
//  RequestsStorageInterface.swift
//  Qonversion
//

import Foundation

protocol RequestsStorageInterface: Sendable {

    /// Persists a failed retriable request for the offline replay. Skips the
    /// request when one with the same non-nil dedupKey is already queued.
    func append(_ request: StoredRequest)

    /// Removes a delivered request from the queue.
    func remove(_ request: StoredRequest)

    func removeAll(where shouldRemove: @Sendable (StoredRequest) -> Bool)

    func fetchRequests() -> [StoredRequest]

    /// Bumped by every clean(). A replay working from a snapshot compares it
    /// to tell whether the queue it is draining still belongs to the current
    /// user.
    var cleanGeneration: Int { get }

    func clean()
}
