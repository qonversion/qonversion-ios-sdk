//
//  DeferredPurchase.swift
//  Qonversion
//

import Foundation

extension Qonversion {

    /// A purchase that completed outside of a ``Qonversion/Qonversion/purchase(_:options:)``
    /// call: an Ask to Buy or SCA approval, a subscription renewal, a refund,
    /// or a purchase made on another device.
    ///
    /// The transaction is part of the signal on purpose: a consumable grants
    /// no entitlement, so the entitlements alone would not tell the host that
    /// anything happened.
    public struct DeferredPurchase: Sendable {

        /// Where the entitlements of this purchase come from.
        public enum EntitlementsSource: Sendable {

            /// The Qonversion backend resolved them.
            case backend

            /// The backend was unreachable, so the SDK calculated them from
            /// the local StoreKit data and the cached product mapping.
            case localCalculation
        }

        /// The store transaction behind the purchase.
        public let transaction: Qonversion.Transaction

        /// The user's entitlements keyed by entitlement id.
        public let entitlements: [String: Qonversion.Entitlement]

        /// Whether the entitlements are backend-resolved or locally calculated.
        public let entitlementsSource: EntitlementsSource
    }
}
