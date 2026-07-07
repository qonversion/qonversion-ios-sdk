//
//  StoredRequest.swift
//  Qonversion
//

import Foundation

/// A failed retriable request persisted for the offline replay. Headers are
/// intentionally not stored — they are rebuilt fresh on resend.
struct StoredRequest: Codable, Equatable {

    let url: String
    let method: String
    let body: Data?

    /// Identifies the payload (e.g. by transaction id) so the same failed
    /// request never queues twice. Nil disables deduplication.
    let dedupKey: String?
}
