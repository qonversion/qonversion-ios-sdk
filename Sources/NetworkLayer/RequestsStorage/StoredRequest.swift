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
}
