//
//  RequestsStorageInterface.swift
//  Qonversion
//

import Foundation

protocol RequestsStorageInterface {

    /// Persists a failed retriable request for the offline replay.
    func append(_ request: StoredRequest)

    func fetchRequests() -> [StoredRequest]

    func clean()
}
