//
//  RequestsStorageInterface.swift
//  Qonversion
//

import Foundation

protocol RequestsStorageInterface {

    /// Persists a failed retriable request for the offline replay. Skips the
    /// request when one with the same non-nil dedupKey is already queued.
    func append(_ request: StoredRequest)

    /// Removes a delivered request from the queue.
    func remove(_ request: StoredRequest)

    func fetchRequests() -> [StoredRequest]

    func clean()
}
