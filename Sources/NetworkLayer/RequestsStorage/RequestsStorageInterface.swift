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

    /// Atomically swaps a queued request for an updated copy of itself, and
    /// only while the queue still belongs to the same user: a clean() in
    /// between must not be undone by the replacement.
    func replace(_ request: StoredRequest, with replacement: StoredRequest, ifGenerationIs generation: Int)

    func removeAll(where shouldRemove: @Sendable (StoredRequest) -> Bool)

    func fetchRequests() -> [StoredRequest]

    /// Bumped by every clean(). A replay working from a snapshot compares it
    /// to tell whether the queue it is draining still belongs to the current
    /// user.
    var cleanGeneration: Int { get }

    func clean()
}
