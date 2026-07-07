//
//  EntitlementsManagerInterface.swift
//  Qonversion
//

import Foundation

protocol EntitlementsManagerInterface {

    /// Returns the user's entitlements keyed by entitlement id.
    ///
    /// On success the persistent cache is refreshed. On a 5xx / connection
    /// error the entitlements are calculated locally from the StoreKit
    /// transactions and the cached product → permissions mapping, merged on
    /// top of the cached entitlements, persisted and returned (production
    /// fault-tolerance behavior). Other errors are rethrown.
    func entitlements() async throws -> [String: Qonversion.Entitlement]

    /// The production fault-tolerance path, reusable from the purchase and
    /// restore flows: calculates entitlements locally for the given
    /// transactions, merges them on top of the cached ones, persists the
    /// result and returns it. Never throws.
    func localFallbackEntitlements(for transactions: [Qonversion.Transaction]) async -> [String: Qonversion.Entitlement]
}
