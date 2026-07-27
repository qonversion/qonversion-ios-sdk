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

    /// The original flow that produced the request — replayed in the Trigger
    /// header on resend.
    let trigger: String?

    /// How many times the request has been sent so far.
    let attempt: Int

    /// The store transaction this request reports, when it reports one. A
    /// delivered report evicts its queued copy by this value: substring
    /// matching on the dedup key could evict an unrelated purchase whose uid
    /// happens to end the same way.
    let transactionId: String?

    init(url: String, method: String, body: Data?, dedupKey: String?, trigger: String? = nil, attempt: Int = 1, transactionId: String? = nil) {
        self.url = url
        self.method = method
        self.body = body
        self.dedupKey = dedupKey
        self.trigger = trigger
        self.attempt = attempt
        self.transactionId = transactionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        method = try container.decode(String.self, forKey: .method)
        body = try container.decodeIfPresent(Data.self, forKey: .body)
        dedupKey = try container.decodeIfPresent(String.self, forKey: .dedupKey)
        // Entries queued by older SDK builds carry neither field.
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger)
        attempt = try container.decodeIfPresent(Int.self, forKey: .attempt) ?? 1
        transactionId = try container.decodeIfPresent(String.self, forKey: .transactionId)
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case method
        case body
        case dedupKey
        case trigger
        case attempt
        case transactionId
    }
}
