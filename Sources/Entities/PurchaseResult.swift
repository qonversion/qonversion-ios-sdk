//
//  PurchaseResult.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// The outcome of a successful purchase: the verified store transaction
    /// and the user's entitlements. When the backend was unreachable, the
    /// entitlements are calculated locally (production fault-tolerance
    /// behavior) and the purchase still succeeds for the integrator.
    public struct PurchaseResult {

        /// The purchase transaction that was verified by the store.
        public let transaction: Qonversion.Transaction

        /// The user's entitlements keyed by entitlement id.
        public let entitlements: [String: Qonversion.Entitlement]
    }
}
