//
//  EntitlementsManagerInterface.swift
//  Qonversion
//

import Foundation

/// Entitlements plus where they actually came from. The fault-tolerance path
/// answers successfully with locally calculated data, so a caller that has to
/// label the provenance (the deferred purchase signal) cannot infer it from
/// the absence of an error.
struct ResolvedEntitlements: Sendable {

    let entitlements: [String: Qonversion.Entitlement]
    let source: Qonversion.DeferredPurchase.EntitlementsSource
}

protocol EntitlementsManagerInterface {

    /// Returns the user's entitlements keyed by entitlement id.
    ///
    /// On success the persistent cache is refreshed. On any failure the
    /// entitlements are calculated locally from the StoreKit transactions and
    /// the cached product → permissions mapping, merged on top of the cached
    /// entitlements, persisted and returned (production fault-tolerance
    /// behavior). The error surfaces only when there is nothing to serve.
    func entitlements() async throws -> [String: Qonversion.Entitlement]

    /// Same as ``entitlements()``, telling the caller whether the backend
    /// answered or the result was calculated locally.
    func resolvedEntitlements() async throws -> ResolvedEntitlements

    /// The production fault-tolerance path, reusable from the purchase and
    /// restore flows: calculates entitlements locally for the given
    /// transactions, merges them on top of the cached ones, persists the
    /// result and returns it. Never throws.
    func localFallbackEntitlements(for transactions: [Qonversion.Transaction]) async -> [String: Qonversion.Entitlement]
}
