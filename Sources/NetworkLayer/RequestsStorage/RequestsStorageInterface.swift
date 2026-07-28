//
//  RequestsStorageInterface.swift
//  Qonversion
//

import Foundation

protocol RequestsStorageInterface: Sendable {

    /// Persists a failed retriable request for the offline replay, and only
    /// while the queue still belongs to the same user: the request was sent
    /// for the uid that was current when it was enqueued, so a clean() that
    /// landed while it was in flight (user switch) must not be undone by its
    /// failure. Skips the request when one with the same non-nil dedupKey is
    /// already queued.
    func append(_ request: StoredRequest, ifGenerationIs generation: Int)

    /// Removes a delivered request from the queue.
    func remove(_ request: StoredRequest)

    /// Atomically swaps a queued request for an updated copy of itself, and
    /// only while the queue still belongs to the same user: a clean() in
    /// between must not be undone by the replacement.
    func replace(_ request: StoredRequest, with replacement: StoredRequest, ifGenerationIs generation: Int)

    /// Drops every queued request the predicate matches, and only while the
    /// queue still belongs to the same user: entries appended after a clean()
    /// (user switch) are the new user's and no longer superseded by whatever
    /// the previous one delivered.
    func removeAll(ifGenerationIs generation: Int, where shouldRemove: @Sendable (StoredRequest) -> Bool)

    func fetchRequests() -> [StoredRequest]

    /// Bumped by every clean(). A replay working from a snapshot compares it
    /// to tell whether the queue it is draining still belongs to the current
    /// user.
    var cleanGeneration: Int { get }

    func clean()
}

extension RequestsStorageInterface {

    /// Enqueues against the generation the queue has right now — for callers
    /// that hold no earlier snapshot of it (there was no window in which a
    /// user switch could have happened behind their back).
    func append(_ request: StoredRequest) {
        append(request, ifGenerationIs: cleanGeneration)
    }

    func removeAll(where shouldRemove: @Sendable (StoredRequest) -> Bool) {
        removeAll(ifGenerationIs: cleanGeneration, where: shouldRemove)
    }
}
